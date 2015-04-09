module CataBot
  module Plugin
    module Jq
      VERSION = '0.0.1'
      GLOB = File.join(CataBot.config['cata'], 'data', 'json', '**/*.json')
      JQ_BIN = '/usr/bin/jq'
      LIMIT = 5
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
          id = @@mutex.synchronize do
            @@id += 1
            @@queries[m.user.mask] = true
            @@id
          end

          results = {'main' => Array.new, 'exceptions' => Array.new}
          begin
            Dir.glob(File.expand_path(GLOB)) do |p|
              io = IO.popen([JQ_BIN, query, p, :err=>[:child,:out]])
              output = io.read
              head = output.lines.first.chop
              if GROUPS.member? head
                results[head] ||= Array.new
                results[head].push(p)
              else
                results['main'].push("#{p}:\n#{output}")
              end
            end
          rescue StandardError => e
            CataBot.log :error, "Something went wrong with jq query '#{query}' from '#{m.user.mask}' at #{e.backtrace.first}"
            results['exceptions'].push('Sorry, something went wrong...')
          end

          @@results[id.to_s] = {data: results, stamp: Time.now}
          url = "#{CataBot.config['web']['url']}/jq/#{id}"
          @@mutex.synchronize { @@queries.delete(m.user.mask) }
          m.reply "Done, have a look at #{url}", true
        end

        get '/:id' do
          id = params['id']
          if @@results.has_key? id
            data = @@results[id][:data]
            text = String.new
            if data['main'].any?
              text += data.delete('main').join("\n")
            else
              text += 'No general results.'
            end
            text += "\n\n"
            data.each_pair do |g, d|
              text += "Resulted in '#{g}':\n"
              text += d.join("\n")
            end
            reply(text, 200, {'Content-Type' => 'text/plain'})
          else
            reply_err('Not found.')
          end
        end
      end
      Web.mount('/jq', App)

      class IRC
        include Cinch::Plugin
        set :prefix, /#{CataBot.config['irc']['nick']}.? /i

        CataBot::IRC.cmd('jq', 'Issue a jq command. See \'jq help\'.')
        match /jq (\w+) ?(.*)?$/, method: :jq
        def jq(m, cmd, rest)
          case cmd
          when 'help'
            m.reply 'Can do: jq version, jq query [query].', true
          when 'version'
            jver = `jq --version`.gsub("\n", '')
            cver = `cd #{CataBot.config['cata']}; git describe --tags --always --dirty`.gsub("\n", '')
            m.reply "You can run #{jver} queries against #{cver}.", true
          when 'query'
            ok, msg = App.can_query?(m.user)
            unless ok
              m.reply msg, true
              return
            end
            App.query(m, rest)
          else
            m.reply 'Perhaps ask me \'jq help\'?', true
          end
        end
      end
    end
  end
end
