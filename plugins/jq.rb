require 'chronic'

module CataBot
  module Plugin
    module Jq
      VERSION = '0.0.2'

      BASEDIR = File.expand_path(CataBot.config['cata'])
      JSONDIR = File.join(BASEDIR, 'data', 'json')
      JQ = File.expand_path(CataBot.config['params']['jq']['jq_bin'])
      GIT = File.expand_path(CataBot.config['params']['jq']['git_bin'])
      LIMIT = CataBot.config['params']['jq']['limit']
      EXPIRE = CataBot.config['params']['jq']['expire']
      GROUPS = %w{null [] {} true false 0}

      class App < Web::App
        @@results = Hash.new
        @@queries = Hash.new
        @@id = 0
        @@mutex = Mutex.new

        def self.can_query?(user)
          @@mutex.synchronize do
            if @@queries.length >= LIMIT
              [false, 'Sorry, I\'m too busy now. Ask later maybe?']
            else
              if @@queries.has_key? user.mask
                [false, 'I\'m still working on your last query.']
              else
                true
              end
            end
          end
        end

        def self.query(m, query)
          at = Time.now

          id = @@mutex.synchronize do
            @@id += 1
            @@queries[m.user.mask] = true
            @@id
          end

          exceptions = Array.new
          results = {'main' => Array.new}
          Dir.chdir(JSONDIR)
          Dir.glob('**/*.json') do |p|
            begin
              fname = 
              io = IO.popen([JQ, query, p, :err=>[:child,:out]])
              output = io.read
              head = output.lines.first.chop
              if GROUPS.member? head
                results[head] ||= Array.new
                results[head].push(p)
              else
                results['main'].push("#{p}:\n#{output}")
              end
            rescue StandardError => e
              CataBot.log :error, "Something went wrong with jq query '#{query}' for #{p} from '#{m.user.mask}'"
              CataBot.log :exception, e
              exceptions.push(p)
            end
          end

          text = "Results for query \"#{query}\"\n\n"
          if results['main'].any?
            text += results.delete('main').join("\n")
          else
            text += 'No general results.'
          end
          text += "\n\n"
          results.each_pair do |g, d|
            text += "Resulted in \"#{g}\":\n"
            text += d.join("\n")
            text += "\n"
          end
          if exceptions.any?
            text += "I had problems processing these files:\n"
            text += exceptions.join("\n")
            text += "\n"
          end
          text += "Processing took #{Time.now - at} seconds."

          @@mutex.synchronize do
            @@results[id.to_s] = {text: text, stamp: Time.now}
            @@queries.delete(m.user.mask)
          end

          url = "#{CataBot.config['web']['url']}/jq/#{id}"
          m.reply "Done, have a look at #{url}", true
        end

        get '/:id' do
          id = params['id']
          @@mutex.synchronize do
            if @@results.has_key? id
              reply(@@results[id][:text], 200, {'Content-Type' => 'text/plain'})
            else
              reply_err('Not found.')
            end
          end
        end

        CataBot.add_thread :jq_expire do
          loop do
            sleep(5 * 60)
            CataBot.log :debug, 'Running JQ cleaner thread...'
            threshold = Chronic.parse(EXPIRE)
            deleted = 0
            @@results.each_pair do |k, v|
              if v[:stamp] < threshold
                @@mutex.synchronize { @@results.delete(k) }
                deleted += 1
              end
            end
            CataBot.log :debug, "JQ cleaner: #{deleted} deleted, #{@@results.length} kept"
          end
        end
      end
      Web.mount('/jq', App)

      class IRC
        include Cinch::Plugin
        set :prefix, /#{CataBot.config['irc']['nick']}.? /i

        CataBot::IRC.cmd('jq', 'Issue a jq command. See "jq help".')
        match /jq (\w+) ?(.*)?$/, method: :jq
        def jq(m, cmd, rest)
          case cmd
          when 'help'
            m.reply 'Can do: jq version, jq query [query].', true
          when 'version'
            jver = `#{JQ} --version`.chop
            cver = `cd #{BASEDIR}; #{GIT} describe --tags --always --dirty`.chop
            m.reply "You can run #{jver} queries against #{cver}.", true
          when 'query'
            ok, msg = App.can_query?(m.user)
            unless ok
              m.reply msg, true
              return
            end
            App.query(m, rest)
          else
            m.reply 'Perhaps ask me "jq help"?', true
          end
        end
      end
    end
  end
end
