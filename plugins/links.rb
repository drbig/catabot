require 'net/http'
require 'uri'
require 'nokogiri'

module CataBot
  module Plugin
    module Links
      VERSION = '0.0.2'

      SCHEMES = %w{http https ftp ftps}

      class Link
        include DataMapper::Resource

        property :url, String, :key => true
        property :channel, String, :length => 1..64, :required => true
        property :user, String, :length => 1..128, :required => true
        property :stamp, Time, :default => Proc.new { Time.now }, :required => true

        property :header, Boolean, :default => false
        property :type, String
        property :size, Integer
        property :filename, String
        property :title, String
      end

      class IRC
        include Cinch::Plugin
        set :prefix, /#{CataBot.config['irc']['nick']}.? /i

        listen_to :message, method: :input
        def input(m)
          return unless m.message.match(/\w+:\/\/.*?/)
          URI.extract(m.message).each do |url|
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

            unless Link.get(url)
              entry = Link.new(url: url, channel: m.channel, user: m.user.mask)
              unless entry.save
                CataBot.log :error, "Links: Error saving entry for #{url}!"
                return false
              end
              Thread.new do
                uri = URI.parse(url)
                begin
                  resp = Net::HTTP.get_response(uri)
                  title = resp['content-type'].match(/text\/html/) \
                    ? Nokogiri.parse(resp.body).title : nil
                  entry.update(:header => true,
                               :type => resp['content-type'],
                               :size => resp['content-length'],
                               :filename => resp['content-disposition'],
                               :title => title)
                rescue Exception => e
                  CataBot.log :warn, "Links: HTTP GET failed for #{url}"
                  CataBot.log :exception, e
                end
              end
            end
          end
        end

        CataBot::IRC.cmd('links', 'Show latest recorded links')
        match /links$/, method: :links
        def links(m)
          links = Link.all(order: [:stamp.desc], limit: 5)
          if links.any?
            m.reply 'Recent links:', true
            links.each_with_index do |l, i|
              m.reply "#{i}. #{l.url}", true
            end
          else
            m.reply 'Don\'t have any links on record', true
          end
        end

        match /link$/, method: :link_help
        def link_help(m)
          m.reply 'Ask me: "link [link]"', true
        end

        CataBot::IRC.cmd('link', 'Show [link] info')
        match /link (.*)$/, method: :link
        def link(m, query)
          if link = Link.get(query)
            msg = "I've seen #{link.url} first mentioned on #{link.channel} at #{link.stamp.utc.strftime('%Y-%m-%d %H:%M:%S %Z')}"
            msg += ", title \"#{link.title}\"" if link.title
            m.reply msg, true
          else
            m.reply 'Don\'t recall such link', true
          end
        end
      end
    end
  end
end
