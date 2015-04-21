require 'addressable/uri'
require 'httparty'

module CataBot
  module Plugin
    module GitHub
      VERSION = '0.0.4'

      AGENT = 'drbig/catabot'
      LIMIT = CataBot.config['params']['github']['limit']
      REPO = CataBot.config['params']['github']['repo']
      BASE = 'https://api.github.com'
      URL = "#{BASE}/repos/#{REPO}"

      class IRC
        include Cinch::Plugin
        set :prefix, /#{CataBot.config['irc']['nick']}.? /i

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

        CataBot::IRC.cmd('github', 'Query CDDA\'s GitHub repo. See "github help"')
        match /github ?(\w+)? ?(.*)?$/, method: :github
        def github(m, cmd, rest)
          case cmd
          when 'help'
            m.reply 'Can do: github recent, github link [number], github about [number], github search [query]', true
          when 'recent'
            query(m, "#{URL}/pulls", state: 'closed') do |res|
              m.reply 'Recent merged PRs:', true
              res.slice(0, 3).each do |pr|
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
                m.reply "##{res['number']} #{res['state']} #{type} by #{res['user']['login']}", true
                m.reply "title: \"#{res['title']}\"", true
                m.reply "for more see: #{res['html_url']}", true
              end
            end
          when 'search'
            if rest.empty?
              m.reply 'Please specify some query...', true
            else
              query(m, "#{BASE}/search/issues", q: "repo:#{REPO} #{rest}") do |res|
                m.reply "Your query matched #{res['total_count']} issues/PRs, top matches:", true
                res['items'].slice(0, 3).each do |i|
                  m.reply "##{i['number']} \"#{i['title']}\"", true
                end
              end
            end
          else
            m.reply 'Perhaps ask me "github help"?', true
          end
        end
      end
    end
  end
end
