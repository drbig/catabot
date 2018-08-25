
module CataBot
  module Plugin
    module WordCount

      class IRC
        include CataBot::IRC::Plugin

        class Counter
          include DataMapper::Resource

          property :channel, String, key: true
          property :nick, String, key: true
          property :date, Date, default: Proc.new { Date.today }
          property :words, Integer, default: 0
        end

        CataBot.finalizer(:wordcount) do
          today = Date.today
          @@top_mutex.synchronize do
            @@counters.each_pair do |chan, h1|
              h1.each_pair do |nick, data|
                record = Counter.first(channel: chan, nick: nick, date: today)
                if record
                  record.words = data[:today]
                else
                  record = Counter.new(channel: chan, nick: nick, date: today, words: data[:today])
                end
                unless record.save
                  CataBot.log :error, "WordCount: Error saving record: #{record}!"
                end
              end
            end
          end
        end

        @@top_mutex = Mutex.new
        @@counters = Hash.new do |h1, chan|
          h1[chan] = Hash.new do |h2, nick|
            today = Date.today
            past_words = Counter.all(:channel => chan, :nick => nick, :date.lt => today).sum(:words) || 0
            today_words = Counter.all(channel: chan, nick: nick, date: today).sum(:words) || 0
            h2[nick] = {today: today_words, past: past_words, mutex: Mutex.new}
          end
        end

        listen_to :channel, method: :input
        def input(m)
          return unless m.channel?
          nick = m.user.nick
          word_count = m.message.split.length
          data = @@counters[m.channel][m.user.nick]
          data[:mutex].synchronize { data[:today] += word_count }
        end

        HELP = '???'
        command(:words, /words ?(\w+)$/, 'words [...]', HELP)
        def words(m, cmd)
          case cmd
          when 'debug'
            data = @@counters[m.channel][m.user.nick]
            data[:mutex].synchronize { m.reply data, true }
          end
        end
      end
    end
  end
end
