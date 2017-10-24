# bigchaindb-ruby-client

> Ruby library that uses BigchainDB's CLI tool to prepare/sign transactions and submit them to IPDB or a BigchainDB Node.

# Installation

As a prerequisite, you must have BigchainDB's CLI tool in your path: 
https://github.com/bigchaindb/bdb-transaction-cli

Then install this project from RubyGems:

```bash
gem install bigchaindb
```

# Usage

```
irb> require 'bigchaindb'
irb> Bdb.generate_keys
```
See example of a full transaction flow in [`lib/bigchaindb.rb`](./lib/bigchaindb.rb)

# Testing

```
IPDB_APP_ID=<app_id> IPDB_APP_KEY=<app_key> ruby test.rb
```
