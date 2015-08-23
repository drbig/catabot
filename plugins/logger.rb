require 'chronic'
require 'tzinfo'
require 'uri'

module CataBot
  module Plugin
    module Logger
      TEMPLATE = Haml::Engine.new(File.read('data/logger/browse.haml'))
      URL = CataBot.config['params']['logger']['url']
      STAMP_FMT = CataBot.config['params']['logger']['stamp_fmt']
      TZ = TZInfo::Timezone.get(CataBot.config['params']['logger']['timezone'])

      class Snippet
        include DataMapper::Resource

        property :name, String, length: 1..64, key: true
        property :from, Time, required: true
        property :to, Time, required: true

        property :channel, String, length: 1..64, required: true
        property :user, String, length: 1..128, required: true
        property :stamp, Time, default: Proc.new { Time.now }, required: true

        def target_link
          from = self.from.strftime(STAMP_FMT)
          to = self.to.strftime(STAMP_FMT)
          URL % {channel: URI.encode(self.channel.to_s), from: from, to: to}
        end

        def redir_link
          URI.join(CataBot.config['web']['url'], "logger/go/#{self.name}").to_s
        end
      end

      class App < Web::App
        get '/go/:name' do
          snippet = Snippet.get(params['name'])
          if snippet
            [302, {location: snippet.target_link}, ['Off you go!']]
          else
            [404, {'Content-Type' => 'text/plain'}, 'Not Found']
          end
        end

        get '/browse' do
          channel = URI.decode(params['channel'] || '')
          page = params['page'] || 1
          chans = Snippet.all(fields: [:channel], unique: true).map(&:channel)
          snippets = Snippet.all(channel: channel, order: [:stamp.desc])
          html = TEMPLATE.render(self, {snippets: snippets, channels: chans, channel: channel})
          reply(html, 200, {'Content-Type' => 'text/html'})
        end
      end
      Web.mount('/logger', App)

      class IRC
        include CataBot::IRC::Plugin

        HELP = 'Can do: log since [x minutes ago] as [name], log for [name], log about [name], log del [name], log links'
        command(:log, /log ?(\w+)? ?(.*)?$/, 'log [...]', HELP)
        def log(m, cmd, rest)
          url = "#{CataBot.config['web']['url']}/logger"
          if !m.channel?
            m.reply "Use on a channel or browse via #{url}/browse", true
            return
          end
          case cmd
          when 'help'
            m.reply HELP, true
          when 'since'
            if mr = rest.match(/(.*?) as (\S+)$/)
              time_str, name = mr.captures
            else
              m.reply 'Syntax error... Please read help and try again :)', true
              return
            end
            if Snippet.get(name)
              m.reply "Sorry, already recorded #{name}. Try another name or delete the existning one?", true
              return
            end
            begin
              from = Chronic.parse(time_str)
              raise StandardError if from.nil?
            rescue StandardError
              m.reply 'Ugh, didn\'t understand your [x minutes ago]. Try again?', true
              return
            end
            from = TZ.utc_to_local(from.utc)
            to = TZ.utc_to_local(Time.now.utc)
            snippet = Snippet.new(name: name, from: from, to: to,
                                  channel: m.channel, user: m.user.mask)
            unless snippet.save
              CataBot.log :error, "Logger: Error saving new: #{snippet}!"
              m.reply 'Erm, something went wrong. I\'ve logged the fact', true
              return
            end
            m.reply "Link: #{snippet.redir_link}"
          when 'for'
            name = rest
            unless name =~ /^\S+$/
              m.reply 'Sorry, name must be a string', true
              return
            end
            snippet = Snippet.get(name)
            unless snippet
              m.reply "Sorry, couldn't find snippet #{name}", true
              return
            end
            m.reply "Link: #{snippet.redir_link}"
          when 'about'
            name = rest
            unless name =~ /^\S+$/
              m.reply 'Sorry, name must be a string', true
              return
            end
            snippet = Snippet.get(name)
            unless snippet
              m.reply "Sorry, couldn't find snippet #{name}", true
              return
            end
            m.reply "#{name} by #{Cinch::Mask.new(snippet.user).nick} added on #{snippet.stamp.utc.strftime('%Y-%m-%d %H:%M:%S UTC')}"
            m.reply "it covers #{snippet.from.strftime('%Y-%m-%d %H:%M:%S %Z')} - #{snippet.to.strftime('%Y-%m-%d %H:%M:%S %Z')}"
          when 'del'
            name = rest
            unless name =~ /^\S+$/
              m.reply 'Sorry, name must be a string', true
              return
            end
            snippet = Snippet.get(name)
            unless snippet
              m.reply "Sorry, couldn't find snippet #{name}", true
              return
            end
            mask = Cinch::Mask.new(snippet.user)
            if mask.match(m.user.mask) || ADMIN.match(m.user.mask)
              unless snippet.destroy
                CataBot.log :error, "Logger: Error destroying: #{snippet}!"
                m.reply 'Erm, something went wrong. I\'ve logged the fact', true
                return
              end
              m.reply "Log snippet #{name} removed"
            else
              m.user.msg "Sorry. You don't look like author of #{name}"
            end
          when 'links'
            m.reply "See: #{url}/browse?channel=#{URI.encode(m.channel.to_s)}", true
          else
            m.reply 'Sorry, didn\'t get that... ' + HELP, true
          end
        end
      end
    end
  end
end
