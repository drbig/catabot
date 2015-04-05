#!/usr/bin/env ruby

require 'logger'
require 'json'
require 'yaml'

require 'cinch'
require 'eldr'
require 'dm-core'
require 'rack'
require 'thin'

module CataBot
  VERSION = '0.0.2'

  class Error < StandardError; end

  @@config = Hash.new
  def self.config; @@config; end
  def self.config=(obj); @@config = obj; end
  def self.log(level, &blk); @@config[:logger].send(level, &blk) if @@config[:logger]; end

  module IRC
    @@cmds = Hash.new
    def self.cmds; @@cmds; end
    def self.cmd(name, desc)
      raise Error, "IRC Command '#{name}' already registered." if @@cmds.has_key? name
      @@cmds[name] = desc
    end
  end

  module Web
    @@mounts = Hash.new
    def self.mounts; @@mounts; end
    def self.mount(root, app)
      raise Error, "Web app already mounted at '#{root}'." if @@mounts.has_key? root
      @@mounts[root] = app
    end

    @@apps = Hash.new
    def self.apps; @@apps; end
    def self.apps=(obj); @@apps = obj; end

    class App < Eldr::App
      def reply_ok(data); reply({success: true, data: data}.to_json); end
      def reply_err(msg); reply({success: false, error: msg}.to_json); end
      
      private
      def reply(data, status = 200)
        Rack::Response.new(data, status, {'Content-Type' => 'application/json'})
      end
    end
  end

  def self.fire!
    c = @@config

    lt = if lf = c['runtime']['logging']['file'] =='stdout'
           STDERR.reopen(STDOUT)
           STDOUT
         else
           File.open(File.expand_path(lf), 'a')
         end
    lt.sync = true if c['runtime']['logging']['sync']
    lg = if ro = c['runtime']['logging']['rotate']
           Logger.new(lt, *ro)
         else
           Logger.new(lt)
         end
    lg.level = Logger.const_get(c['runtime']['logging']['level'].upcase)
    lg.formatter = if c['runtime']['logging']['stamp']
                     lambda do |s,d,p,m|
                       "#{Time.now.strftime('%Y-%m-%d %H:%M:%S.%3N')} | #{s.ljust(5)} | #{m}\n"
                     end
                   else
                     lambda {|s,d,p,m| "#{s.ljust(5)} | #{m}\n" }
                   end
    @@config[:logger] = lg

    self.log(:info) { 'Setting up database...'}
    DataMapper.finalize
    DataMapper.setup(:default, c['database'])
    if m = c['database'].match(/sqlite:\/\/(.*?)/) # TODO: broken?
      p = m.captures.first
      unless File.exists? p
        require 'dm-migrations'
        DataMapper.auto_migrate!
      end
    end

    self.log(:debug) { 'Loading IRC code...' }
    c['plugins'].each {|p| require_relative File.join('plugins', "#{p.downcase}.rb") }

    self.log(:info) { 'Configuring web backend...' }
    app = Rack::Builder.new do
      CataBot::Web.mounts.each_pair do |r, a|
        ap = CataBot::Web.apps[a.to_s] = a.new
        map r do run ap end
      end
    end.to_app

    self.log(:info) { 'Configuring IRC bot...' }
    bot = Cinch::Bot.new do
      configure do |b|
        b.nick      = c['irc']['nick']
        b.user      = c['irc']['user']
        b.realname  = c['irc']['realname']
        b.server    = c['irc']['server']
        b.channels  = c['irc']['channels']

        b.plugins.plugins = c['plugins'].map {|p| CataBot.const_get(p + 'Plugin') }
      end
    end

    self.log(:info) { 'Starting Web backend...' }
    web = Thread.new do
      Rack::Handler::Thin.run(app, {
        :Host => c['web']['host'] || '127.0.0.1',
        :Port => c['web']['port'] || 8080,
      })
    end

    self.log(:info) { 'Starting IRC bot...' }
    irc = Thread.new { bot.start }

    web.join
    self.log(:debug) { 'Web thread ended...' }
  end
end

unless ARGV.length == 1
  STDERR.puts "Usage: #{$PROGRAM_NAME} cofig.yaml"
  exit(2)
end

begin
  c = CataBot.config = File.open(ARGV.first) {|f| YAML.load(f.read) }
  if c['runtime']['daemon']
    pid = fork { CataBot.fire! }
    if pf = c['runtime']['pid_file']
      pid_path = File.expand_path(pf)
      File.open(pid_path, 'w') {|f| f.puts pid }
    end
    Process.detach(pid)
  else
    CataBot.fire!
  end
rescue StandardError => e
  msg = "Runtime error: #{e.to_s} at #{e.backtrace.first}."
  CataBot.log(:fatal) { msg }
  CataBot.log(:debug) { e.backtrace.join("\n") }
  STDERR.puts msg
  exit(3)
end
