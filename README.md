# catabot

A plugin-based IRC bot framework that also provides easy Web interfaces and periodic code execution. Written in [Ruby](https://www.ruby-lang.org/en/) on top of [Cinch](https://github.com/cinchrb/cinch) (for IRC) and [Eldr](https://github.com/eldr-rb/eldr) (for Web). Comes with a number of useful and configurable plugins.

Current status: *look good*

Configuration is done via a single [YAML](http://yaml.org/) file, see `example.yaml`.

Requires at least modern [Ruby](https://www.ruby-lang.org/en/), a bunch of GEMs (see `Gemfile`) and some database ([SQLite](https://www.sqlite.org/) will do too). Exact dependencies depend on which plugins you want to use.

## Plugin showcase

 * Base
   - Basic infrastructure for other plugins
   - Common help system and bot-wide commands
 * Clock
   - Show current time in a different timezone
 * Seen
   - Show last time the bot has seen a nick
   - Supports wildcards
 * Memo
   - Take notes for nicks not currently present
   - Per-channel public memos and global privmsg memos
   - Wildcarded nick matching, so `John_` will get the message for `John`
 * Links
   - Gather links posted to channels
   - Includes link checking to provided page title where possible
   - Has a web page for recent links with channel filtering
 * Facts
   - Per-channel facts database with public adding and voting
   - Think of it as a simple keyword-based micro Wiki
   - Has web pages for searching per-channel and a global recent facts page
 * GitHub
   - Quick IRC interface to a GitHub repository
   - Includes full-blown issue/pr search interface via IRC
   - Show recently merged, pending, link, details...
 * Jenkins
   - Quick IRC interface to a Jenkins instance
   - Show last builds, particular build details...
 * Jq
   - Run [jq](http://stedolan.github.io/jq/) queries on some data directory
   - Results shown via web interface

Most plugins adapt their output based on if asked on channel vs. via a privmsg.

```
< user> help .*
<  bot> version - Tells you the version
<  bot> plugins - Tells you what plugins are loaded
<  bot> help - Tells you what commands are available
<  bot> help [command] - Tells you basic [command] help
<  bot> source - Gives you the link to my source code
<  bot> seen [nick] - Check last known presence of [nick]. Accepts wildcards
<  bot> memo [...] - Can do: memo pending, memo tell [nick] [message], memo forget [nick]
<  bot> links [...] - Can do: links recent, links about [link]
<  bot> jq [...] - Can do: jq wtf, jq version, jq query [query], jq last
<  bot> github [...] - Can do: github pending, github recent, github link [number], github about [number], github search [query]
<  bot> jenkins [...] - Can do: jenkins last, jenkins recent, jenkins about [number]
<  bot> time [zone] - Show current time in [zone]
<  bot> facts [...] - Can do: facts all [keyword], facts add [keyword] [text], facts vote [up|down] [id], facts about [id], facts del [id], facts stats, facts links
```

## Contributing

Follow the usual GitHub workflow:

 1. Fork the repository
 2. Make a new branch for your changes
 3. Work (and remember to commit with decent messages)
 4. Push your feature branch to your origin
 5. Make a Pull Request on GitHub

## Licensing

Standard two-clause BSD license, see LICENSE.txt for details.

Copyright (c) 2015 Piotr S. Staszewski

