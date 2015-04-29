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
          property :cmd, String, required: true, length: 1..32
          property :stamp, DateTime, required: true
          property :mask, String, length: 3..256
          property :channel, String, length: 1..64

          def reply
            at = self.stamp.to_time.utc.strftime('%Y-%m-%d %H:%M:%S UTC')
            where = self.channel ? " on #{self.channel}" : ''
            "at #{at} (#{self.cmd}#{where})"
          end
        end

        def record(m, u = nil)
          user = u || m.user
          ns = NickSeen.first_or_create(nick: user.nick)
          ns.cmd = m.command.to_s.downcase
          ns.stamp = DateTime.now

          begin
            mask = user.mask
            ns.mask = mask
          rescue StandardError
            # just leave the mask as it was
          end

          begin
            chan = m.channel.to_s
            chan = nil if chan.empty?
          rescue StandardError
            chan = nil
          ensure
            ns.channel = chan
          end

          ns.save
        end

        listen_to :join, method: :join
        def join(m); record(m); end

        listen_to :leaving, method: :leaving
        def leaving(m, user); record(m, user); end

        command(:seen, /seen (.*)$/, 'seen [nick]', 'Check last known presence of [nick]')
        def seen(m, query)
          if ns = NickSeen.get(query)
            m.reply "Last seen #{query} #{ns.reply}", true
          else
            m.reply "Don't recall seeing #{query}", true
          end
        end

        CataBot.aux_thread(:seen_expire, 24 * 60 * 60) do
          threshold = Chronic.parse(EXPIRE).to_datetime
          expired = NickSeen.all(:stamp.lt => threshold)
          deleted = 0

          if expired.any?
            deleted = expired.length
            unless expired.destroy
              CataBot.log :error, "Couldn't destroy expired last seen data: #{expired.errors.join(', ')}"
            end
          end

          CataBot.log :debug, "Seen cleaner: #{deleted} deleted, #{NickSeen.count} kept"
        end
      end
    end
  end
end
