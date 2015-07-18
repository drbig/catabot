require 'httparty'

module CataBot
  module Plugin
    module Jenkins
      LIMIT = CataBot.config['params']['jenkins']['limit']
      URL = CataBot.config['params']['jenkins']['url']

      def self.query(url, &blk)
        begin
          res = HTTParty.get(url + '/api/json')
          CataBot.log :debug, "Jenkins query for #{url} code: #{res.code}"
          if res.code == 200 && res.any?
            [true, blk.call(res)]
          else
            [false, 'Sorry, seems I didn\'t get any results']
          end
        rescue StandardError => e
          CataBot.log :error, "Something went wrong with a Jenkins query for '#{url}'"
          CataBot.log :exception, e
          [false, 'Sorry, something seems to have gone wrong. Things have been logged']
        end
      end

      class App < Web::App
        get '/version/:build' do
          unless bm = params['build'].match(/^#?(\d+)$/)
            reply('Please use a valid Jenkins build number, e.g. 3245',
                  200, {'Content-Type' => 'text/plain'})
          else
            number = bm.captures.first
            _, msg = Jenkins.query("#{URL}/#{number}") do |res|
              begin
                res['actions'][3]['buildsByBranchName']['origin/master']['revision']['SHA1'].slice(0, 7)
              rescue StandardError => e
                CataBot.log :warn, 'Jenkins: Error parsing additional about data'
                CataBot.log :exception, e
                'Sorry, something seems to have gone wrong. Things have been logged'
              end
            end
            reply(msg, 200, {'Content-Type' => 'text/plain'})
          end
        end
      end
      Web.mount('/jenkins', App)

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

          success, msg = Jenkins.query(url, &blk)
          m.reply msg, true unless success
          @@mutex.synchronize { @@queries.delete(m.user.mask) }
        end

        HELP = 'Can do: jenkins last, jenkins recent, jenkins about [number]'
        command(:jenkins, /jenkins ?(\w+)? ?(.*)?$/, 'jenkins [...]', HELP)
        def jenkins(m, cmd, rest)
          case cmd
          when 'help'
            m.reply HELP, true
          when 'last'
            id = nil
            query(m, URL) do |res_a|
              id = res_a['lastSuccessfulBuild']['number']
            end
            return unless id
            query(m, "#{URL}/#{id}") do |res_b|
              begin
                commitish = 'g' + res_b['actions'][3]['buildsByBranchName']['origin/master']['revision']['SHA1'].slice(0, 7)
                stamp = Time.at(res_b['timestamp'].to_f / 1000.0).utc.strftime('%Y-%m-%d %H:%M:%S %Z')
                m.reply "##{id} #{res_b['result']} at #{commitish} on #{stamp}", true
              rescue StandardError => e
                CataBot.log :warn, 'Jenkins: Error parsing additional about data'
                CataBot.log :exception, e
                m.reply 'Sorry, something seems to have gone wrong. Things have been logged', true
                end
              end
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
