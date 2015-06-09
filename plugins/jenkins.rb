require 'httparty'

module CataBot
  module Plugin
    module Jenkins
      LIMIT = CataBot.config['params']['jenkins']['limit']
      URL = CataBot.config['params']['jenkins']['url']

      class IRC
        include CataBot::IRC::Plugin

        @@queries = Hash.new
        @@mutex = Mutex.new

        def query(m, url, &blk)
          raise ArgumentError, 'No block given' if blk.nil?

          @@mutex.synchronize do
            if @@queries.length >= LIMIT
              m.reply 'Sorry, I\'m too busy now. Ask later maybe?', true
              return
            end
            if @@queries.has_key? m.user.mask
              m.reply 'I\'m still working on your last query.', true
              return
            end
            @@queries[m.user.mask] = true
          end

          begin
            res = HTTParty.get(url + '/api/json')
            CataBot.log :debug, "Jenkins query for #{url} code: #{res.code}"
            if res.code == 200 && res.any?
              blk.call(res)
            else
              m.reply 'Sorry, seems I didn\'t get any results', true
            end
          rescue StandardError => e
            CataBot.log :error, "Something went wrong with a Jenkins query for '#{url}'"
            CataBot.log :exception, e
            m.reply 'Sorry, something seems to have gone wrong. Things have been logged', true
          ensure
            @@mutex.synchronize { @@queries.delete(m.user.mask) }
          end
        end

        HELP = 'Can do: jenkins recent, jenkins about [number]'
        command(:jenkins, /jenkins ?(\w+)? ?(.*)?$/, 'jenkins [...]', HELP)
        def jenkins(m, cmd, rest)
          case cmd
          when 'help'
            m.reply HELP, true
          when 'recent'
            query(m, URL) do |res|
              numbers = %w{lastBuild lastSuccessfulBuild}.map {|k| res[k]['number'] }
              if numbers[0] == numbers[1]
                m.reply "Last build: #{numbers[0]} (successful)", true
              else
                m.reply "Last build: #{numbers[0]}, last successful: #{numbers[1]}", true
              end
            end
          when 'about'
            unless rm = rest.match(/^#?(\d+)$/)
              m.reply 'Wrong build id, use e.g. "jenkins about #1234"', true
            else
              number = rm.captures.first
              query(m, "#{URL}/#{number}") do |res|
                m.reply "##{number} #{res['result']} \"#{res['actions'][0]['causes'][0]['shortDescription']}\"", true
                begin
                  culprits = res['culprits'].map {|x| x['fullName'] }.join(', ')
                  commitish = 'g' + res['actions'][3]['buildsByBranchName']['origin/master']['revision']['SHA1'].slice(0, 7)
                  stamp = Time.at(res['timestamp'].to_f / 1000.0).utc.strftime('%Y-%m-%d %H:%M:%S %Z')
                  m.reply "culprits: #{culprits}; at #{commitish} on #{stamp}", true 
                rescue StandardError => e
                  CataBot.log :warn, 'Jenkins: Error parsing additional about data'
                  CataBot.log :exception, e
                end
              end
            end
          else
            m.reply 'Sorry, didn\'t get that... ' + HELP, true
          end
        end
      end
    end
  end
end
