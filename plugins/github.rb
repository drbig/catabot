require 'addressable/uri'
require 'chronic'
require 'httparty'

module CataBot
  module Plugin
    module GitHub
      AGENT = CataBot.config['params']['github']['agent']
      LIMIT = CataBot.config['params']['github']['limit']
      REPO = CataBot.config['params']['github']['repo']
      BASE = 'https://api.github.com'
      URL = "#{BASE}/repos/#{REPO}"

      class IRC
        include CataBot::IRC::Plugin

        @@queries = Hash.new
        @@mutex = Mutex.new

        def query(m, url, params = {}, &blk)
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
            res = HTTParty.get(url, query: params, headers: {'User-Agent' => AGENT})
            CataBot.log :debug, "GitHub query for #{url} code: #{res.code}"
            if res.code == 200 && res.any?
              blk.call(res)
            else
              m.reply 'Sorry, seems I didn\'t get any results', true
            end
          rescue StandardError => e
            CataBot.log :error, "Something went wrong with a GitHub query for '#{url}'"
            CataBot.log :exception, e
            m.reply 'Sorry, something seems to have gone wrong. Things have been logged', true
          ensure
            @@mutex.synchronize { @@queries.delete(m.user.mask) }
          end
        end

        HELP = 'Can do: github pending, github recent, github link [number], github about [number], github search [query]'
        command(:github, /github ?(\w+)? ?(.*)?$/, 'github [...]', HELP)
        def github(m, cmd, rest)
          case cmd
          when 'help'
            m.reply HELP, true
          when 'pending'
            stamp = Chronic.parse('3 days ago').strftime('%Y-%m-%d')
            query(m, "#{BASE}/search/issues", q: "repo:#{REPO} is:pr is:open updated:>=#{stamp} NOT wip in:title") do |res|
              limit = m.channel? ? 3 : 10
              m.reply 'Fresh pending PRs:', true
              res['items'].slice(0, limit).each do |i|
                m.reply "##{i['number']} \"#{i['title']}\"", true
              end
            end
          when 'recent'
            query(m, "#{URL}/pulls", state: 'closed') do |res|
              limit = m.channel? ? 3 : 10
              m.reply 'Recent merged PRs:', true
              res.slice(0, limit).each do |pr|
                m.reply "##{pr['number']} \"#{pr['title']}\"", true
              end
            end
          when 'link'
            unless rm = rest.match(/^#?(\d+)$/)
              m.reply 'Wrong issue/PR id, use e.g. "github about #1234"', true
            else
              query(m, "#{URL}/issues/#{rm.captures.first}") do |res|
                m.reply "##{res['number']} #{res['html_url']}", true
              end
            end
          when 'about'
            unless rm = rest.match(/^#?(\d+)$/)
              m.reply 'Wrong issue/PR id, use e.g. "github about #1234"', true
            else
              query(m, "#{URL}/issues/#{rm.captures.first}") do |res|
                type = res.has_key?('pull_request') ? 'PR' : 'Issue'
                begin
                  stamp = Time.parse(res['updated_at']).utc.strftime('%Y-%m-%d %H:%M:%S %Z')
                  stamp = " (last update: #{stamp})"
                rescue StandardError => e
                  stamp = ''
                  CataBot.log :warn, 'GitHub: Error parsing updated_at'
                  CataBot.log :exception, e
                end

                m.reply "##{res['number']} \"#{res['title']}\"", true
                m.reply "#{res['state']} #{type} by #{res['user']['login']}#{stamp}, #{res['html_url']}", true
              end
            end
          when 'search'
            if rest.empty?
              m.reply 'Please specify some query...', true
            else
              query(m, "#{BASE}/search/issues", q: "repo:#{REPO} #{rest}") do |res|
                limit = m.channel? ? 3 : 10
                m.reply "Your query matched #{res['total_count']} issues/PRs, top matches:", true
                res['items'].slice(0, limit).each do |i|
                  m.reply "##{i['number']} \"#{i['title']}\"", true
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
