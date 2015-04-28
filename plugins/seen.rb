require 'chronic'

module CataBot
  module Plugin
    module Seen
      VERSION = '0.0.5'

      EXPIRE = CataBot.config['params']['seen']['expire']

      class IRC
        include CataBot::IRC::Plugin

        class NickSeen
          include DataMapper::Resource

          property :nick, String, key: true, length: 1..16

          property :mask, String, required: true, length: 3..256
          property :channel, String, required: true, length: 1..64
          property :stamp, DateTime, required: true
          property :cmd, String, required: true, length: 1..32

          def reply
            at = self.stamp.to_time.utc.strftime('%Y-%m-%d %H:%M:%S UTC')
            "at #{at} (#{self.cmd} @ #{self.channel})"
          end
        end

        def record(m, u = nil)
          user = u || m.user
          ns = NickSeen.first_or_create(nick: user.nick)
          ns.mask = user.mask
          ns.channel = m.channel.to_s
          ns.stamp = DateTime.now
          ns.cmd = m.command.to_s.downcase
          ns.save!
        end

        listen_to :join, method: :join
        def join(m)
          CataBot.log :debug, "Seen #{m.user.nick} joining"
          record(m)
        end

        listen_to :leaving, method: :leaving
        def leaving(m, user)
          CataBot.log :debug, "Seen #{m.user.nick} leaving (c: #{m.command}, e: #{m.events.join('; ')})"
          record(m, user)
        end

        command(:seen, /seen nick (.*)$/, 'seen nick [nick]', 'Check last known presence of [nick]')
        def seen(m, query)
          if ns = NickSeen.get(query)
            m.reply "Last seen #{query} #{ns.reply}", true
          else
            m.reply "Don't recall seeing #{query}", true
          end
        end

        #CataBot.aux_thread(:seen_expire, 24 * 60 * 60) do
        #  threshold = Chronic.parse(EXPIRE)
        #  deleted = 0
        #  @@seen.each_pair do |k, v|
        #    if v[:stamp] < threshold
        #      @@mutex.synchronize { @@seen.delete(k) }
        #      deleted += 1
        #    end
        #  end
        #  CataBot.log :debug, "Seen cleaner: #{deleted} deleted, #{@@seen.length} kept"
        #end
      end
    end
  end
end
