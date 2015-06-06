module CataBot
  module Plugin
    module Facts
      MIN_SCORE = CataBot.config['params']['facts']['min_score']
      TEMPLATES = Hash[Dir.glob('data/facts/*.haml').collect do |p|
        name = File.basename(p, '.haml').to_sym
        [name, Haml::Engine.new(File.read(p))]
      end]

      class Fact
        include DataMapper::Resource

        property :id, Serial
        property :keyword, String, length: 1..64, required: true
        property :text, Text, required: true
        property :score, Integer, default: 1, required: true

        property :channel, String, length: 1..64, required: true
        property :user, String, length: 1..128, required: true
        property :stamp, Time, default: Proc.new { Time.now }, required: true
      end

      class App < Web::App
        get '/recent' do
          recent = Fact.all(order: [:stamp.desc], limit: 32)
          html = TEMPLATES[:recent].render(self, {recent: recent})
          reply(html, 200, {'Content-Type' => 'text/html'})
        end
      end
      Web.mount('/facts', App)

      class IRC
        include CataBot::IRC::Plugin

        @@mutex = Mutex.new
        @@voters = Hash.new
        def self.reset_voters!
          @@mutex.synchronize { @@voters.clear }
        end

        HELP = 'Can do: facts [keyword], fact add [keyword] [text], fact vote [up|down] [id], fact about [id], fact del [id], fact stats'
        command(:facts, /(facts?) ?(\w+)? ?(.*)?$/, 'fact', 'Ask about facts I know. See "fact help"')
        def facts(m, cmd, scmd, rest)
          unless m.channel?
            m.reply 'This only works in the context of a channel', true
            return
          end
          if cmd == 'facts'
            keyword = scmd.downcase
            facts = Fact.all(keyword: keyword, order: [:score.desc], channel: m.channel)
            if facts.empty?
              m.reply "Sorry, have nothing about '#{keyword}'. Maybe add some facts about it?", true
            else
              msg = "#{keyword}: "
              msg += facts.map {|f| "(#{f.id}) #{f.text}" }.join(', ')
              m.reply msg
            end
          else
            case scmd
            when 'help'
              m.reply HELP, true
            when 'add'
              keyword, *text = rest.split(/\s+/)
              keyword.downcase!
              text = text.join(' ')
              if keyword.empty? || text.empty?
                m.reply 'Sorry, you need to specify a keyword and some fact about it', true
                return
              end
              fact = Fact.new(keyword: keyword, text: text, channel: m.channel, user: m.user.mask)
              unless fact.save
                CataBot.log :error, "Facts: Error saving new: #{fact}!"
                m.reply 'Erm, something went wrong. I\'ve logged the fact', true
                return
              end
              m.reply "Learnt fact (#{fact.id}) about #{keyword}. Anyone can vote it up or down"
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
              fact = Fact.get(id.to_i)
              unless fact
                m.reply "Sorry, couldn't find fact (#{id})", true
                return
              end
              key = "#{m.user.mask}-#{id}"
              if @@voters.has_key? key
                m.reply "You've already voted for #{id} today, try tomorrow", true
                return
              end
              if dir == :up
                fact.score += 1
              else
                fact.score -= 1
              end
              if fact.score <= MIN_SCORE
                unless fact.destroy
                  CataBot.log :error, "Facts: Error destroying: #{fact}!"
                  m.reply 'Erm, something went wrong. I\'ve logged the fact', true
                  return
                end
                m.reply "Fact (#{fact.id}) was wrong by popular vote. Already forgot it"
              else
                unless fact.save
                  CataBot.log :error, "Facts: Error saving voted: #{fact}!"
                  m.reply 'Erm, something went wrong. I\'ve logged the fact', true
                  return
                end
                m.user.msg "Fact (#{fact.id}) has now score of #{fact.score}"
              end
              @@voters[key] = true
            when 'del'
              id = rest
              unless id =~ /^\d+$/
                m.reply 'Sorry, id must be a number', true
                return
              end
              fact = Fact.get(id.to_i)
              unless fact
                m.reply "Sorry, couldn't find fact (#{id})", true
                return
              end
              mask = Cinch::Mask.new(fact.user)
              if mask.match(m.user.mask)
                unless fact.destroy
                  CataBot.log :error, "Facts: Error destroying by owner: #{fact}!"
                  m.reply 'Erm, something went wrong. I\'ve logged the fact', true
                  return
                end
                m.reply "Fact (#{fact.id}) removed by author"
              else
                m.user.msg "Sorry. You don't look like author of fact (#{fact.id})"
              end
            when 'about'
              id = rest
              unless id =~ /^\d+$/
                m.reply 'Sorry, id must be a number', true
                return
              end
              fact = Fact.get(id.to_i)
              unless fact
                m.reply "Sorry, couldn't find fact (#{id})", true
                return
              end
              m.reply "(#{fact.id}) by #{Cinch::Mask.new(fact.user).nick} added on #{fact.stamp.utc.strftime('%Y-%m-%d %H:%M:%S UTC')}, score: #{fact.score}"
            when 'stats'
              all = Fact.all(channel: m.channel).count
              keywords = Fact.all(fields: [:keyword], unique: true, channel: m.channel).count
              m.reply "I know #{all} facts across #{keywords} keywords"
            else
              m.reply 'Sorry, didn\'t get that... ' + HELP, true
            end
          end
        end

        CataBot.aux_thread(:facts_clean, 24 * 60 * 60) { IRC.reset_voters! }
      end
    end
  end
end
