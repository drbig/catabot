require 'uri'

module CataBot
  module Plugin
    module Quotes
      TEMPLATES = Hash[Dir.glob('data/quotes/*.haml').collect do |p|
        name = File.basename(p, '.haml').to_sym
        [name, Haml::Engine.new(File.read(p))]
      end]

      class Quote
        include DataMapper::Resource

        property :id, Serial
        property :text, Text, required: true

        property :channel, String, length: 1..64, required: true
        property :user, String, length: 1..128, required: true
        property :stamp, Time, default: Proc.new { Time.now }, required: true

        def format_id
          "(#{self.id})"
        end

        def format_stamp
          self.stamp.utc.strftime('%Y-%m-%d %H:%M:%S UTC')
        end

        def format_full
          "#{format_id} #{self.text}"
        end

        def format_short
          "#{format_id} added on #{format_stamp}"
        end

        def format_info
          "#{format_id} added on #{format_stamp} by #{self.user.split('!').first}"
        end
      end

      class App < Web::App
        MOUNT_AT = '/quotes'

        get '/recent' do
          recent = Quote.all(order: [:stamp.desc], limit: 50)
          html = TEMPLATES[:recent].render(self, {recent: recent})
          reply(html, 200, {'Content-Type' => 'text/html'})
        end

        get '/browse' do
          channel = URI.decode(params['channel'] || '')
          search = params['search']
          page = params['page'] || 1
          chans = Quote.all(fields: [:channel], unique: true).map(&:channel)
          query = {channel: channel, order: [:stamp.desc]}
          query[:text.like] = "%#{URI.decode(search)}%" if search && !search.empty?
          quotes = Quote.all(query)
          html = TEMPLATES[:browse].render(self, {quotes: quotes, channels: chans,
                                                  channel: channel, search: search})
          reply(html, 200, {'Content-Type' => 'text/html'})
        end
      end
      Web.mount(App::MOUNT_AT, App)

      class IRC
        include CataBot::IRC::Plugin

        def has_quotes(m)
          return true if Quote.count(channel: m.channel) > 0

          m.reply 'Sorry I know no quotes...', true
          false
        end

        HELP = 'Can do: quote random, quote last, quote like [text], quote get [id], quote about [id], quote del [id], quote stats, quote links'
        command(:quote, /quote ?(\w+)? ?(.*)?$/, 'quote [...]', HELP)
        def quote(m, cmd, rest)
          url = "#{CataBot.config['web']['url']}#{App::MOUNT_AT}"
          if !m.channel? && cmd != 'help'
            m.reply "Use on a channel or via #{url}/browse", true
            return
          end
          case cmd
          when 'help'
            m.reply HELP, true
          when 'links'
            m.reply "See: #{url}/browse?channel=#{URI.encode(m.channel.to_s)} and/or #{url}/recent", true
          when 'add'
            if rest.empty?
              m.reply "I do need that quote first...", true
              return
            end
            quote = Quote.new(text: rest, channel: m.channel, user: m.user.mask)
            unless quote.save
              CataBot.log :error, "Quotes: Error saving new: #{quote}!"
              m.reply 'Erm, something went wrong. I\'ve logged the fact', true
              return
            end
            m.reply "Memorised quote (#{quote.id})."
          when 'last'
            return unless has_quotes(m)
            quote = Quote.last(channel: m.channel)
            m.reply quote.format_full, false
          when 'about'
            return unless has_quotes(m)
            unless rest =~ /^\d+$/
              m.reply 'Sorry, id must be a number', true
              return
            end
            quote = Quote.get(rest.to_i)
            unless quote
              m.reply "Sorry, couldn't find quote (#{rest})", true
              return
            end
            if quote.channel != m.channel
              m.reply "Sorry, couldn't find quote (#{rest})", true
              return
            end
            m.reply quote.format_info, false
          when 'like'
            return unless has_quotes(m)
            if rest.empty?
              m.reply 'Sorry, need to know what to look for...', true
              return
            end
            head, *tail = Quote.all(:text.like => "%#{rest}%", :channel => m.channel)
            if !head
              m.reply 'Sorry, didn\'t find anything like it...', true
              return
            end
            m.reply head.format_full, false
            unless tail.empty?
              m.reply "Also matched #{tail.map(&:format_id).join(', ')}", false
            end
          when 'get'
            return unless has_quotes(m)
            unless rest =~ /^\d+$/
              m.reply 'Sorry, id must be a number', true
              return
            end
            quote = Quote.get(rest.to_i)
            unless quote
              m.reply "Sorry, couldn't find quote (#{rest})", true
              return
            end
            if quote.channel != m.channel
              m.reply "Sorry, couldn't find quote (#{rest})", true
              return
            end
            m.reply quote.format_full, false
          when 'random'
            return unless has_quotes(m)
            ids = Quote.all(channel: m.channel, fields: [:id])
            quote = Quote.get(ids[rand(ids.length)].id)
            m.reply quote.format_full, false
            return
          when 'stats'
            return unless has_quotes(m)
            count = Quote.count(channel: m.channel)
            quote = Quote.last(channel: m.channel)
            m.reply "I've memorised #{count} quote(s), last one was #{quote.format_short}"
          when 'del'
            return unless has_quotes(m)
            unless rest =~ /^\d+$/
              m.reply 'Sorry, id must be a number', true
              return
            end
            quote = Quote.get(rest.to_i)
            unless quote
              m.reply "Sorry, couldn't find quote (#{rest})", true
              return
            end
            mask = Cinch::Mask.new(quote.user)
            should_delete = false
            if CataBot::IRC::Plugin::ADMIN.match(m.user.mask)
              should_delete = true
              m.reply 'You\'re the god!', true
            elsif mask.match(m.user.mask)
              should_delete = true
              m.reply 'As you wish', true
            else
              m.reply 'Sorry, it\'s not yours to remove...', true
              return
            end
            if should_delete
              unless quote.destroy
                CataBot.log :error, "Quotes: Error destroying #{quote}!"
                m.reply 'Erm, something went wrong. I\'ve logged the fact', true
                return
              end
              m.reply "Quote (#{quote.id}) has been forgotten."
            end
          end
        end
      end
    end
  end
end
