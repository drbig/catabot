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

        private
        def clean_time_string(string)
          cleaned = string.gsub(' ', '_').downcase
          TZ_MAP.fetch(cleaned, string)
        end
      end
    end
  end
end
