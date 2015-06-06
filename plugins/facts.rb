module CataBot
  module Plugin
    module Facts
      MIN_SCORE = CataBot.config['params']['facts']['min_score']

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

      class IRC
        include CataBot::IRC::Plugin

        HELP = 'Can do: facts [keyword], fact add [keyword] [text], fact vote [up|down] [id], fact stats'
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
                m.reply "Fact (#{fact.id}) has now score of #{fact.score}"
              end
            when 'stats'
              all = Fact.all(channel: m.channel).count
              keywords = Fact.all(fields: [:keyword], unique: true, channel: m.channel).count
              m.reply "I know #{all} facts across #{keywords} keywords"
            else
              m.reply 'Sorry, didn\'t get that... ' + HELP, true
            end
          end
        end
      end
    end
  end
end
