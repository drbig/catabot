# catabot

A plugin-based IRC bot with plugins useful to [Cataclysm: Dark Days Ahead](http://en.cataclysmdda.com/) community.

*Note*: General bot's infrastructure and half of the plugins is *generally* useful and not specific to CDDA.

Features:
 - Modular framework for IRC (channel, privmsg) *and* web interfaces
 - Rich(er) general plugins: memos, last seen, links
 - CDDA plugins: GitHub queries, Jenkins queries, [jq](http://stedolan.github.io/jq/) runner

Current status: *looks OK*

Configuration is done via a single [YAML](http://yaml.org/) file, see `example.yaml`.

Requires at least modern [Ruby](https://www.ruby-lang.org/en/), a bunch of GEMs (see `Gemfile`) and some database ([SQLite](https://www.sqlite.org/) will do too). Exact dependencies depend on which plugins you want to use.

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

