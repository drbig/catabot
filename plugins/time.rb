require 'tzinfo/data'
require 'tzinfo'

module CataBot
  module Plugin
    module Time
      VERSION = '0.0.1'

      class IRC
        include CataBot::IRC::Plugin

        command(:time, /time (.*)$/, 'time [zone]', 'Show current time in [zone]')
        def time(m, query)
          query.gsub!(' ', '_')
          begin
            zone = TZInfo::Timezone.get(query)
          rescue TZInfo::InvalidTimezoneIdentifier
            m.reply 'Couldn\'t find that zone. Maybe try US/Pacific or Europe/Warsaw', true
          else
            m.reply "in #{zone.friendly_identifier} it's #{zone.now.strftime('%H:%M:%S (%Y-%m-%d)')}"
          end
        end
      end
    end
  end
end
