module CataBot
  module Plugin
    module Base
      VERSION = '0.0.1'

      class App < Web::App
        get '/versions' do
          reply_ok({
            version: CataBot::VERSION,
            plugins: CataBot.config['plugins'].map do |p|
              {p => CataBot::Plugin.const_get(p).const_get('VERSION')}
            end
          })
        end
      end
      CataBot::Web.mount('/', App)

      class IRC
        include Cinch::Plugin
        set :prefix, /#{CataBot.config['irc']['nick']}.? /i

        listen_to :connect, method: :setup
        def setup(m)
          User('Nickserv').send("IDENTIFY #{CataBot.config['irc']['pass']}")
        end

        CataBot::IRC.cmd('version', 'Tells you the version')
        match /version$/, method: :version
        def version(m)
          m.reply "I'm Catabot v#{CataBot::VERSION}", true
        end

        CataBot::IRC.cmd('plugins', 'Tells you what plugins are loaded')
        match /plugins$/, method: :plugins
        def plugins(m)
          m.reply "I have loaded: #{CataBot.config['plugins'].join(', ')}", true
        end

        CataBot::IRC.cmd('help', 'Tells you what commands are available')
        match /help$/, method: :help_all
        def help_all(m)
          m.reply "I can reply to: #{CataBot::IRC.cmds.keys.join(', ')}", true
        end

        CataBot::IRC.cmd('help [command]', 'Describes the given command')
        match /help (\w+)/, method: :help_cmd
        def help_cmd(m, arg)
          cmd = arg.downcase
          if CataBot::IRC.cmds.has_key? cmd
            m.reply "\"#{cmd}\": #{CataBot::IRC.cmds[cmd]}", true
          else
            m.reply 'I don\'t know this command', true
          end
        end
      end
    end
  end
end
