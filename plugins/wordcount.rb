
module CataBot
  module Plugin
    module WordCount

      class IRC
        include CataBot::IRC::Plugin

        class Counter
          include DataMapper::Resource

          property :id, Serial
          property :channel, String, required: true
          property :nick, String, required: true
          property :date, Date, default: Proc.new { Time.now.utc.to_date }, required: true
          property :words, Integer, default: 0
        end

        @@top_mutex = Mutex.new
        @@counters = Hash.new do |h1, chan|
          h1[chan] = Hash.new do |h2, nick|
            today = Time.now.utc.to_date
            today_words = Counter.all(channel: chan, nick: nick, date: today).sum(:words) || 0
            h2[nick] = {today: today_words, mutex: Mutex.new}
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

        HELP = 'Can do: words place (nick), words ttop10, words top10'
        command(:words, /words ?(\w+) ?(\S+)?$/, 'words [...]', HELP)
        def words(m, cmd, rest)
          if !m.channel? && cmd != 'help'
            m.reply 'Use on a channel', true
            return
          end
          case cmd
          when 'help'
            m.reply HELP, true
          when 'place'
            data = get_ranking(m.channel)
            nick = rest || m.user.nick
            place = data.find_index {|e| e.first == nick}
            if !place
              m.reply "Sorry, don't know #{nick}...", true
              return
            end
            words = data[place].last
            m.reply "#{nick} is \##{place+1} (with #{words} words) out of #{data.length}"
          when 'top10'
            data = get_ranking(m.channel)
            msg = data[0..9].each_with_index.map {|(nick, count), idx| "#{idx+1}. #{nick} (#{count})" }.join(', ')
            m.reply "Overall top 10: #{msg}"
          when 'debug'
            data = @@counters[m.channel][m.user.nick]
            data[:mutex].synchronize { m.reply data, true }
          end
        end

        def get_ranking(chan)
          today = Time.now.utc.to_date
          data = Counter.aggregate(:nick, :words.sum, :conditions => {:channel => chan, :date.lt => today})
          @@top_mutex.synchronize do
            if @@counters.has_key? chan
              @@counters[chan].each_pair do |t_nick, t_data|
                idx = data.find_index {|e| e.first == t_nick}
                if idx
                  data[idx][1] += t_data[:today]
                else
                  data << [t_nick, t_data[:today]]
                end
              end
            end
          end
          data.sort {|a, b| b.last <=> a.last }
        end

        def self.save_state(today)
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
                data[:today] = 0
              end
            end
          end
        end

        CataBot.aux_thread_midnight(:wordcount) do
          stamp = Time.now.utc
          stamp -= 24*60*60 if stamp.hour = 0
          IRC.save_state(stamp.to_date)
        end

        CataBot.finalizer(:wordcount) do
          IRC.save_state(Time.now.utc.to_date)
        end
      end
    end
  end
end
