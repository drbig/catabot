module CataBot
  module Plugin
    module Seen
      VERSION = '0.0.2'

      EXPIRE = CataBot.config['params']['jq']['expire']

      class IRC
        include Cinch::Plugin
        set :prefix, /#{CataBot.config['irc']['nick']}.? /i

        @@seen = Hash.new
        @@mutex = Mutex.new

        class LastSeen < Struct.new(:action, :where, :stamp)
          def to_s
            "#{action}ing channel #{where} at #{stamp.utc.strftime('%Y-%m-%d %H:%M:%S UTC')}"
          end
        end

        listen_to :join, method: :join
        def join(m)
          CataBot.log :debug, "Seen #{m.user.nick} joining"
          @@seen[m.user.nick] = LastSeen.new(:join, m.channel, Time.now)
        end

        listen_to :part, method: :part
        def part(m)
          CataBot.log :debug, "Seen #{m.user.nick} parting"
          @@seen[m.user.nick] = LastSeen.new(:part, m.channel, Time.now)
        end

        match /seen$/, method: :seen_help
        def seen_help
          m.reply 'Ask me "seen [nick]"', true
        end

        CataBot::IRC.cmd('seen', 'Check last known presence of [nick]')
        match /seen (.*)$/, method: :seen
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
            sleep(60 * 60)
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
