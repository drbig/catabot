module CataBot
  class BaseApp < Web::App
    get '/version' do
      reply_ok({version: CataBot::VERSION})
    end
  end
  Web.mount('/', BaseApp)

  class BasePlugin
    include Cinch::Plugin
    set :prefix, /#{CataBot.config['irc']['nick']}.? /i

    listen_to :connect, method: :setup
    def setup(m)
      User('Nickserv').send("IDENTIFY #{CataBot.config['irc']['pass']}")
    end

    match /version$/, method: :version
    CataBot::IRC.cmd('version', 'Tells you the version.')
    def version(m)
      m.reply "I'm Catabot v#{CataBot::VERSION}.", true
    end

    match /plugins$/, method: :plugins
    CataBot::IRC.cmd('plugins', 'Tells you what plugins are loaded.')
    def plugins(m)
      m.reply "I have loaded: #{CataBot.config['plugins'].join(', ')}.", true
    end

    match /help$/, method: :help
    CataBot::IRC.cmd('help', 'Tells you what commands are available.')
    def help(m)
      m.reply "I can reply to: #{CataBot::IRC.cmds.keys.join(', ')}.", true
    end

    match /help (\w+)/, method: :help_cmd
    CataBot::IRC.cmd('help [command]', 'Describes the given command.')
    def help_cmd(m, arg)
      cmd = arg.downcase
      if CataBot::IRC.cmds.has_key? cmd
        m.reply "'#{cmd}': #{CataBot::IRC.cmds[cmd]}", true
      else
        m.reply 'I don\'t know this command.', true
      end
    end
  end
end
