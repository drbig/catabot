module CataBot
  module IRC
    module Plugin
      ADMIN = Cinch::Mask.new(CataBot.config['params']['base']['admin'])
      SOURCE = CataBot.config['params']['base']['source']

      def self.included(recv)
        recv.include(Cinch::Plugin)
        recv.set(:prefix, /#{CataBot.config['irc']['nick']}.? /i)

        recv.extend(Methods)
      end

      module Methods
        def command(meth, rexp, name = nil, desc = nil)
          CataBot::IRC.cmd(name, desc) if name && desc
          match(rexp, method: meth, react_on: :channel)
          match(/^#{rexp}/, method: meth, react_on: :private, use_prefix: false)
        end
      end
    end
  end

  module Plugin
    module Base
      class App < Web::App
        get '/plugins' do
          reply_ok({
            version: CataBot.config['runtime']['version'],
            plugins: CataBot.config['plugins'],
          })
        end
      end
      CataBot::Web.mount('/', App)

      class IRC
        include CataBot::IRC::Plugin

        listen_to :connect, method: :setup
        def setup(m)
          User('Nickserv').send("IDENTIFY #{CataBot.config['irc']['pass']}")
          # TODO: if we can't get our config nick die or update the config...
        end

        command(:version, /version$/, 'version', 'Tells you the version')
        def version(m)
          m.reply "I'm Catabot #{CataBot.config['runtime']['version']}", true
        end

        command(:plugins, /plugins$/, 'plugins', 'Tells you what plugins are loaded')
        def plugins(m)
          m.reply "I have loaded: #{CataBot.config['plugins'].join(', ')}", true
        end

        command(:help_global, /help$/, 'help', 'Tells you what commands are available')
        def help_global(m)
          m.reply "I can reply to: #{CataBot::IRC.cmds.keys.sort.join(', ')}", true
        end

        command(:help_command, /help (.+)$/, 'help [command]', 'Tells you basic [command] help')
        def help_command(m, arg)
          cmd = arg.downcase
          matches = CataBot::IRC.cmds.keys.select {|k| k.match(/^#{cmd}.*/) }
          if matches.any?
            matches.each {|k| m.reply "#{k} - #{CataBot::IRC.cmds[k]}", true }
          else
            m.reply 'Can\'t help you with that', true
          end
        end

        command(:admin_quit, /quit$/)
        def admin_quit(m)
          CataBot.stop! if ADMIN.match(m.user.mask)
        end

        command(:source, /source$/, 'source', 'Gives you the link to my source code')
        def source(m)
          m.reply "My code is at: #{SOURCE}", true
        end
      end
    end
  end
end
