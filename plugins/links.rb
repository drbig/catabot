require 'net/http'
require 'uri'
require 'haml'
require 'nokogiri'

module CataBot
  module Plugin
    module Links
      SCHEMES = %w{http https ftp ftps}
      TEMPLATE = Haml::Engine.new(File.read('data/links/recent.haml'))
      EXPIRE = CataBot.config['params']['links']['expire']

      class Link
        include DataMapper::Resource

        property :url, String, key: true
        property :channel, String, length: 1..64, required: true
        property :user, String, length: 1..128, required: true
        property :stamp, Time, default: Proc.new { Time.now }, required: true

        property :header, Boolean, default: false
        property :type, String, length: 1..128
        property :size, Integer
        property :filename, String, length: 1..512
        property :title, String, length: 1..512
      end

      class App < Web::App
        get '/recent' do
          limit = params['limit'].to_i rescue 50
          limit = 50 if limit < 1 || limit > 256
          channel = params['channel']

          if channel && !channel.empty?
            links = Link.all(channel: channel, limit: limit, order: [:stamp.desc])
          else
            channel = nil
            links = Link.all(limit: limit, order: [:stamp.desc])
          end
          chans = Link.all(fields: [:channel], unique: true).map(&:channel)
          html = TEMPLATE.render(self, {links: links, channel: channel, channels: chans})
          reply(html, 200, {'Content-Type' => 'text/html'})
        end
      end
      Web.mount('/links', App)

      class IRC
        include CataBot::IRC::Plugin

        listen_to :channel, method: :input
        def input(m)
          URI.extract(m.message).each do |url|
            next unless url.match(/\w+:\/\/.*?/)
            begin
              uri = URI.parse(url)
            rescue StandardError => e
              CataBot.log :warn, "Links: Rejected '#{url}' on parsing"
              CataBot.log :exception, e
              next
            end

            unless SCHEMES.member? uri.scheme
              CataBot.log :warn, "Links: Ditching #{url} due to unsupported scheme"
              next
            end

            if entry = Link.get(url)
              unless entry.update(channel: m.channel, user: m.user.mask, stamp: Time.now)
                CataBot.log :error, "Links: Error updating basic data for #{url}"
              end
            else
              entry = Link.new(url: url, channel: m.channel, user: m.user.mask)
              unless entry.save
                CataBot.log :error, "Links: Error saving entry for #{url}!"
                return false
              end

              Thread.new do
                res = Array.new
                title = nil
                begin
                  u = URI.parse(url)
                  Net::HTTP.start(u.host, u.port) do |h|
                    res = h.head(u.request_uri)
                    if res['content-type'].match(/text\/html/)
                      res = h.get(u.request_uri)
                      title = Nokogiri::HTML.parse(res.body, nil, 'UTF-8').title
                    end
                  end
                rescue StandardError => e
                  CataBot.log :warn, "Links: Error trying to extract more details for #{url}"
                  CataBot.log :exception, e
                end

                unless entry.update(:header => true,
                                    :type => res['content-type'],
                                    :size => res['content-length'],
                                    :filename => res['content-disposition'],
                                    :title => title)
                  CataBot.log :error, "Links: Error updating details for #{url}"
                end
              end
            end
          end
        end

        HELP = 'Can do: links recent, links about [link]'
        command(:links, /links ?(\w+)? ?(.*)?$/, 'links [...]', HELP)
        def links(m, cmd, rest)
          url = "#{CataBot.config['web']['url']}/links/recent"
          case cmd
          when 'help'
            m.reply HELP, true
          when 'recent'
            if m.channel?
              m.reply "#{url}?channel=#{URI.encode(m.channel.to_s)}", true
            else
              links = Link.all(order: [:stamp.desc], limit: 10)
              if links.any?
                m.reply 'Recent links from all channels:', true
                links.each_with_index do |l, i|
                  m.reply "#{i+1}. #{l.url}", true
                end
              else
                m.reply 'Don\'t have any links on record', true
              end
              m.reply "More at #{url}", true
            end
          when 'about'
            if link = Link.get(rest)
              m.reply "I've seen #{link.url} last mentioned on #{link.channel} at #{link.stamp.utc.strftime('%Y-%m-%d %H:%M:%S %Z')}", true
              m.reply "It was entitled \"#{link.title}\"", true if link.title
            else
              m.reply 'Don\'t recall such link', true
            end
          else
            m.reply 'Sorry, didn\'t get that... ' + HELP, true
          end
        end

        CataBot.aux_thread(:links_expire, 24 * 60 * 60) do
          threshold = Chronic.parse(EXPIRE + ' ago').to_datetime
          expired = Links.all(:stamp.lt => threshold)
          deleted = 0

          if expired.any?
            deleted = expired.length
            unless expired.destroy
              CataBot.log :error, "Couldn't destroy expired links: #{expired.errors.join(', ')}"
            end
          end

          CataBot.log :debug, "Links cleaner: #{deleted} deleted, #{Links.count} kept"
        end
      end
    end
  end
end
