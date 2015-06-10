require 'uri'

module CataBot
  module Plugin
    module Rules
      MIN_SCORE = CataBot.config['params']['rules']['min_score']
      TEMPLATES = Hash[Dir.glob('data/rules/*.haml').collect do |p|
        name = File.basename(p, '.haml').to_sym
        [name, Haml::Engine.new(File.read(p))]
      end]

      class Rule
        include DataMapper::Resource

        property :id, Serial
        property :text, Text, required: true
        property :score, Integer, default: 1, required: true

        property :channel, String, length: 1..64, required: true
        property :user, String, length: 1..128, required: true
        property :stamp, Time, default: Proc.new { Time.now }, required: true
      end

      class App < Web::App
        get '/recent' do
          recent = Rule.all(order: [:stamp.desc], limit: 50)
          html = TEMPLATES[:recent].render(self, {recent: recent})
          reply(html, 200, {'Content-Type' => 'text/html'})
        end

        get '/browse' do
          channel = URI.decode(params['channel'] || '')
          page = params['page'] || 1
          chans = Rule.all(fields: [:channel], unique: true).map(&:channel)
          query = {channel: channel, order: [:stamp.desc]}
          rules = Rule.all(channel: channel, order: [:stamp.desc])
          html = TEMPLATES[:browse].render(self, {rules: rules, channels: chans, channel: channel})
          reply(html, 200, {'Content-Type' => 'text/html'})
        end
      end
      Web.mount('/rules', App)

      class IRC
        include CataBot::IRC::Plugin

        @@mutex = Mutex.new
        @@voters = Hash.new
        def self.reset_voters!
          @@mutex.synchronize { @@voters.clear }
        end

        HELP = 'Can do: rule give, rule show [id], rule add [text], rule vote [up|down] [id], rule about [id], rule del [id], rule stats, rule links'
        command(:rule, /rule ?(\w+)? ?(.*)?$/, 'rule [...]', HELP)
        def rule(m, cmd, rest)
          url = "#{CataBot.config['web']['url']}/rules"
          if !m.channel? && cmd != 'help' 
            m.reply "Use on a channel or via #{url}/browse", true
            return
          end
          case cmd
          when 'help'
            m.reply HELP, true
          when 'give'
            rule = Rule.first(offset: rand(Rule.count))
            if rule
              m.reply "(#{rule.id}) #{rule.text}", true
            else
              m.reply 'Sorry, don\'t have any rules on file here.', true
            end
          when 'links'
            m.reply "See: #{url}/browse?channel=#{URI.encode(m.channel.to_s)} and/or #{url}/recent", true
          when 'show'
            id = rest
            unless id =~ /^\d+$/
              m.reply 'Sorry, id must be a number', true
              return
            end
            rule = Rule.get(id.to_i)
            unless rule
              m.reply "Sorry, couldn't find rule (#{id})", true
              return
            end
            m.reply "(#{rule.id}) #{rule.text}"
          when 'add'
            if rest.empty?
              m.reply 'Sorry, you need to specify a rule body', true
              return
            end
            rule = Rule.new(text: rest, channel: m.channel, user: m.user.mask)
            unless rule.save
              CataBot.log :error, "Rules: Error saving new: #{rule}!"
              m.reply 'Erm, something went wrong. I\'ve logged the fact', true
              return
            end
            m.reply "Noted rule (#{rule.id}). Anyone can vote it up or down"
          when 'vote'
            dir, id = rest.split(/\s+/)
            dir = dir.downcase.to_sym
            if dir != :down && dir != :up
              m.reply 'Sorry, you can only vote \'up\' or \'down\'', true
              return
            end
            unless id =~ /^\d+$/
              m.reply 'Sorry, id must be a number', true
              return
            end
            rule = Rule.get(id.to_i)
            unless rule
              m.reply "Sorry, couldn't find rule (#{id})", true
              return
            end
            key = "#{m.user.mask}-#{id}"
            if @@voters.has_key? key
              m.reply "You've already voted for (#{id}) today, try tomorrow", true
              return
            end
            if dir == :up
              rule.score += 1
            else
              rule.score -= 1
            end
            if rule.score <= MIN_SCORE
              unless rule.destroy
                CataBot.log :error, "Rules: Error destroying: #{rule}!"
                m.reply 'Erm, something went wrong. I\'ve logged the fact', true
                return
              end
              m.reply "Rule (#{rule.id}) was poor by popular vote. Already forgot it"
            else
              unless rule.save
                CataBot.log :error, "Rules: Error saving voted: #{rule}!"
                m.reply 'Erm, something went wrong. I\'ve logged the fact', true
                return
              end
              m.user.msg "Rule (#{rule.id}) has now score of #{rule.score}"
            end
            @@voters[key] = true
          when 'del'
            id = rest
            unless id =~ /^\d+$/
              m.reply 'Sorry, id must be a number', true
              return
            end
            rule = Rule.get(id.to_i)
            unless rule
              m.reply "Sorry, couldn't find rule (#{id})", true
              return
            end
            mask = Cinch::Mask.new(rule.user)
            if mask.match(m.user.mask)
              unless rule.destroy
                CataBot.log :error, "Rules: Error destroying by owner: #{rule}!"
                m.reply 'Erm, something went wrong. I\'ve logged the fact', true
                return
              end
              m.reply "Rule (#{rule.id}) removed by author"
            else
              m.user.msg "Sorry. You don't look like author of rule (#{rule.id})"
            end
          when 'about'
            id = rest
            unless id =~ /^\d+$/
              m.reply 'Sorry, id must be a number', true
              return
            end
            rule = Rule.get(id.to_i)
            unless rule
              m.reply "Sorry, couldn't find rule (#{id})", true
              return
            end
            m.reply "(#{rule.id}) by #{Cinch::Mask.new(rule.user).nick} added on #{rule.stamp.utc.strftime('%Y-%m-%d %H:%M:%S UTC')}, score: #{rule.score}"
          when 'stats'
            all = Rule.all(channel: m.channel).count
            m.reply "I have #{all} rules on file here"
          else
            m.reply 'Sorry, didn\'t get that... ' + HELP, true
          end
        end

        CataBot.aux_thread(:rules_clean, 24 * 60 * 60) { IRC.reset_voters! }
      end
    end
  end
end
