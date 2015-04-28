require 'chronic'

module CataBot
  module Plugin
    module Memo
      VERSION = '0.0.1'

      LIMIT = CataBot.config['params']['memo']['limit']
      EXPIRE = CataBot.config['params']['memo']['expire']

      class IRC
        include CataBot::IRC::Plugin

        @@memos = Hash.new
        @@mutex = Mutex.new

        Note = Struct.new(:who, :when, :where, :for, :body)

        def get_pending(m)
          @@memos.each_value.to_a.flatten.select do |n|
            n.who == m.user.nick && n.where == m.channel
          end
        end

        listen_to :join, method: :join
        def join(m)
          nick = m.user.nick
          @@mutex.synchronize do
            return unless @@memos.has_key? nick
            @@memos[nick].each do |n|
              next unless n.where == m.channel
              m.reply "#{n.who} left a note for you: #{n.body}", true
              @@memos[nick].delete(n)
            end
            @@memos.delete(nick) if @@memos[nick].empty?
          end
        end

        command(:memo, /memo ?(\w+)? ?(.*)$/, 'memo', 'Leave a note for another user. See "memo help"')
        def memo(m, cmd, rest)
          case cmd
          when 'help'
            m.reply 'Can do: memo pending, memo tell [nick] [message], memo forget [nick]', true
          when 'pending'
            notes = get_pending(m)
            if notes.any?
              m.reply "I have your pending notes for #{notes.map(&:for).join(', ')} on file", true
            else
              m.reply 'You don\'t have any notes pending here', true
            end
          when 'tell'
            unless rm = rest.match(/^(.*?)\s+(.*)$/)
              m.reply 'Wrong format, use e.g. "memo tell dRbiG Your bot is great!"', true
            else
              to, body = rm.captures
              if body.empty?
                m.reply 'Your note should have some content...', true
                return
              end

              if m.channel.has_user? to
                m.reply "You can tell that #{to} yourself", true
                return
              end

              notes = get_pending(m)
              if notes.any? {|n| n.for == to }
                m.reply "Sorry, you already have a note pending for #{to}. You can always tell me to forget it...", true
                return
              end

              if @@memos.has_key?(to) && @@memos[to].length > LIMIT
                m.reply "Sorry, I have already too many notes pending for #{to}. I'm not a spam bot you know...", true
                return
              end

              @@mutex.synchronize do
                @@memos[to] ||= Array.new
                @@memos[to].push(Note.new(m.user.nick, Time.now, m.channel, to, body))
              end
              m.reply "Noted down. Will try my best to relay that to #{to}", true
            end
          when 'forget'
            if rest.empty?
              m.reply 'Wrong format, use e.g. "memo forget dRbiG"', true
            else
              unless notes = @@memos[rest]
                m.reply "You haven't left a note for #{rest}", true
              else
                note = notes.select {|n| n.who == m.user.nick && n.where == m.channel }
                unless note && note.any?
                  m.reply "You haven't left a note for #{rest} here", true
                else
                  @@mutex.synchronize { @@memos[rest].delete(note.first) }
                  m.reply "Forgot that note for #{rest}", true
                end
              end
            end
          else
            m.reply 'Perhaps ask me "memo help"?', true
          end
        end

        CataBot.aux_thread(:memos_expire, 4 * 60 * 60) do
          threshold = Chronic.parse(EXPIRE)
          deleted = 0
          kept = 0
          @@memos.each_pair do |u, v|
            v.each do |n|
              if n.when < threshold
                @@mutex.synchronize { v.delete(n) }
                deleted += 1
              else
                kept += 1
              end
              @@mutex.synchronize { @@memos.delete(u) if v.empty? }
            end
          end
          CataBot.log :debug, "Memo cleaner: #{deleted} deleted, #{kept} kept"
        end
      end
    end
  end
end
