require 'tzinfo/data'
require 'tzinfo'

module CataBot
  module Plugin
    module Clock
      class IRC
        include CataBot::IRC::Plugin

        TZ_MAP = TZInfo::Timezone.all.inject(Hash.new) {|acc, tz| acc[tz.name.downcase] = tz.name; acc }

        command(:time_in, /time in (.*)$/, 'time in [where|zone]', 'Show current time in zone or country/place (case-sensitive!)')
        def time_in(m, query)
          query = clean_time_string(query)
          begin
            zone = TZInfo::Timezone.get(query)
          rescue TZInfo::InvalidTimezoneIdentifier
            m.reply 'Couldn\'t find that zone. Maybe try US/Pacific or Europe/Warsaw or CET', true
          else
            m.reply "in #{zone.friendly_identifier} it's #{zone.now.strftime('%H:%M:%S (%Y-%m-%d)')}"
          end
        end

        command(:time_convert, /time from (.*) to (.*)$/, 'time from [(yyyy-mm-dd) hh:mm(:ss) where|zone] to [where|zone]', 'Convert time from origin to target time zone/place (case-sensitive!)')
        def time_convert(m, from, to)
          begin
            time = Time.parse(from)
          rescue ArgumentError
            m.reply "Didn't understand '#{from}', try e.g. '19:00 CET'", true
            return
          end

          to = clean_time_string(to)
          begin
            zone = TZInfo::Timezone.get(to)
          rescue TZInfo::InvalidTimezoneIdentifier
            m.reply "Couldn't understand '#{to}', try e.g. CET or US/Pacific", true
          else
            time_there = time.utc + zone.transitions_up_to(Time.now).last.offset.utc_offset
            m.reply "it'll be #{time_there.strftime('%H:%M:%S (%Y-%m-%d)')} there"
          end
        end

        private
        def clean_time_string(string)
          cleaned = string.gsub(' ', '_').downcase
          TZ_MAP.fetch(cleaned, string)
        end
      end
    end
  end
end
