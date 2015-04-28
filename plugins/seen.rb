require 'chronic'

module CataBot
  module Plugin
    module Seen
      VERSION = '0.0.5'

      EXPIRE = CataBot.config['params']['seen']['expire']

      class IRC
        include CataBot::IRC::Plugin

        @@seen = Hash.new
        @@mutex = Mutex.new

        class LastSeen < Struct.new(:action, :where, :stamp)
          def to_s
            at = stamp.utc.strftime('%Y-%m-%d %H:%M:%S UTC')
            if action == :joined
              "joining #{where} at #{at}"
            else
              "leaving at #{at}"
            end
          end
        end

        listen_to :join, method: :join
        def join(m)
          CataBot.log :debug, "Seen #{m.user.nick} joining"
          @@seen[m.user.nick] = LastSeen.new(:joined, m.channel, Time.now)
        end

        listen_to :leaving, method: :leaving
        def leaving(m, user)
          CataBot.log :debug, "Seen #{m.user.nick} leaving"
          @@seen[m.user.nick] = LastSeen.new(:left, nil, Time.now)
        end

        command(:seen, /seen (.*)$/, 'seen [nick]', 'Check last known presence of [nick]')
        def seen(m, query)
          @@mutex.synchronize do
            if @@seen.has_key? query
              m.reply "Last seen #{query} #{@@seen[query]}", true
            else
              m.reply "Don't recall seeing #{query}", true
            end
          end
        end

        CataBot.add_thread :seen_expire do
          loop do
            sleep(24 * 60 * 60)
            CataBot.log :debug, 'Running Seen cleaner thread...'
            threshold = Chronic.parse(EXPIRE)
            deleted = 0
            @@seen.each_pair do |k, v|
              if v[:stamp] < threshold
                @@mutex.synchronize { @@seen.delete(k) }
                deleted += 1
              end
            end
            CataBot.log :debug, "Seen cleaner: #{deleted} deleted, #{@@seen.length} kept"
          end
        end
      end
    end
  end
end
