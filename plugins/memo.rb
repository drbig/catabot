require 'chronic'

module CataBot
  module Plugin
    module Memo
      LIMIT = CataBot.config['params']['memo']['limit']
      EXPIRE = CataBot.config['params']['memo']['expire']

      class IRC
        include CataBot::IRC::Plugin

        class Note
          include DataMapper::Resource

          property :id, Serial
          property :for, String, required: true, length: 1..16
          property :by, String, required: true, length: 1..16
          property :channel, String, required: true, length: 1..64
          property :stamp, DateTime, required: true, default: Proc.new { DateTime.now }
          property :body, Text, required: true
        end

        listen_to :join, method: :join
        def join(m)
          nicks = Note.all(fields: [:for], unique: true)
          return unless nicks.any?

          matches = nicks.select {|n| m.user.nick.match(/^#{n.for}.*/i) }
          return unless matches.any?

          if matches.length > 1
            CataBot.log :warn, "Multiple memo nick matches for: #{m.user.nick}"
            # well, let's use the first one only anyways
          end

          Note.all(for: matches.first.for).each do |n|
            if n.channel == 'privmsg'
              m.user.send "#{n.by} left a note for you: #{n.body}"
            elsif n.channel == m.channel.to_s
              m.reply "#{n.by} left a note for you: #{n.body}", true
            else
              next
            end
            unless n.destroy
              CataBot.log :error, "Couldn't destroy note: #{n.errors.join(', ')}"
            end
          end
        end

        HELP = 'Can do: memo pending, memo tell [nick] [message], memo forget [nick]'
        command(:memo, /memo ?(\w+)? ?(.*)$/, 'memo [...]', HELP)
        def memo(m, cmd, rest)
          case cmd
          when 'help'
            m.reply HELP, true
          when 'pending'
            if m.channel?
              notes = Note.all(by: m.user.nick, channel: m.channel.to_s)
              if notes.any?
                m.reply "I have your pending notes for #{notes.map(&:for).join(', ')} on file", true
              else
                m.reply 'You don\'t have any notes pending here', true
              end
            else
              notes = Note.all(by: m.user.nick, order: [:channel])
              if notes.any?
                map = Hash.new
                notes.each do |n|
                  map[n.channel] ||= Array.new
                  map[n.channel].push(n)
                end
                msg = 'I have your pending notes for '
                msg += map.each_pair.collect {|c, n| "#{c}: #{n.map(&:for).join(', ')}" }.join('; ')
                m.reply msg, true
              else
                m.reply 'You don\'t have any notes pending', true
              end
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

              if m.channel?
                if m.channel.has_user? to
                  m.reply "You can tell that #{to} yourself", true
                  return
                end
                chan = m.channel.to_s
              else
                chan = 'privmsg'
              end

              if Note.all(for: to, by: m.user.nick, channel: chan).any?
                m.reply "Sorry, you already have a note pending for #{to}. You can always tell me to forget it...", true
                return
              end

              if Note.all(for: to).count >= LIMIT
                m.reply "Sorry, I have already too many notes pending for #{to}. I'm not a spam bot you know...", true
                return
              end

              note = Note.new(for: to, by: m.user.nick, channel: chan, body: body)
              if note.save 
                m.reply "Noted down. Will try my best to relay that to #{to}", true
              else
                CataBot.log :error, "Couldn't save new note: #{note.errors.join(', ')}"
                m.reply 'Something went wrong... Sorry', true
              end
            end
          when 'forget'
            if rest.empty?
              m.reply 'Wrong format, use e.g. "memo forget dRbiG"', true
            else
              if m.channel?
                chan = m.channel.to_s
              else
                chan = 'privmsg'
              end
              notes = Note.all(by: m.user.nick, for: rest, channel: chan)
              if notes.any?
                if notes.destroy
                  m.reply "Forgot that note for #{rest}", true
                else
                  CataBot.log :error, "Couldn't destroy note: #{notes.errors.join(', ')}"
                  m.reply 'Something went wrong... Sorry', true
                end
              else
                if m.channel?
                  m.reply "You haven't left a note for #{rest} here", true
                else
                  m.reply "You haven't left a private note for #{rest}", true
                end
              end
            end
          else
            m.reply 'Sorry, didn\'t get that... ' + HELP, true
          end
        end

        CataBot.aux_thread_every(:memo_expire, 4 * 60 * 60) do
          threshold = Chronic.parse(EXPIRE + ' ago').to_datetime
          expired = Note.all(:stamp.lt => threshold)
          deleted = 0

          if expired.any?
            deleted = expired.length
            unless expired.destroy
              CataBot.log :error, "Couldn't destroy expired memos: #{expired.errors.join(', ')}"
            end
          end

          CataBot.log :debug, "Memo cleaner: #{deleted} deleted, #{Note.count} kept"
        end
      end
    end
  end
end
