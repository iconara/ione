# Ione

[![Build Status](https://travis-ci.org/iconara/ione.png?branch=master)](https://travis-ci.org/iconara/ione)
[![Coverage Status](https://coveralls.io/repos/iconara/ione/badge.png)](https://coveralls.io/r/iconara/ione)
[![Blog](http://b.repl.ca/v1/blog-ione-ff69b4.png)](http://architecturalatrocities.com/tagged/ione)

_If you're reading this on GitHub, please note that this is the readme for the development version and that some features described here might not yet have been released. You can find the readme for a specific version either through [rubydoc.info](http://rubydoc.info/find/gems?q=ione) or via the release tags ([here is an example](https://github.com/iconara/ione/tree/v1.2.0))._

Ione is a framework for reactive programming in Ruby. It is based on the reactive core of [cql-rb](http://github.com/iconara/cql-rb), the Ruby driver for Cassandra.

# Features

## Futures & promises

At the core of Ione is a futures API. Futures make it easy to compose asynchronous operations.

## Streams

Streams are a powerful abstraction for building for example composable protocol parsers.

## Evented IO

A key piece of the framework is an IO reactor with which you can easily build network clients and servers.

### Byte buffer

Networking usually means pushing lots of bytes around and in Ruby it's easy to make the mistake of using strings as buffers. Ione provides an efficient byte buffer implementation as an alternative.

# Examples

The [examples](https://github.com/iconara/ione/tree/master/examples) directory has some examples of what you can do with Ione, for example:

* [redis_client](https://github.com/iconara/ione/tree/master/examples/redis_client) is a more or less full featured Redis client that uses most of Ione's features.
* [http_client](https://github.com/iconara/ione/tree/master/examples/http_client) is a simplistic HTTP client that uses Ione and [http_parser.rb](http://rubygems.org/gems/http_parser.rb) to make HTTP GET request. It also shows how to make TLS connections.
* [cql-rb](https://github.com/iconara/cql-rb) is a high performance Cassandra driver and where Ione was originally developed.
* [cassandra-driver](https://github.com/datastax/ruby-driver) is the successor to cql-rb.
* [ione-rpc](https://github.com/iconara/ione-rpc) is a RPC framework built on Ione. It makes it reasonably easy to build networked applications without having to reinvent the wheel.

# How to contribute

[See CONTRIBUTING.md](CONTRIBUTING.md)

# Copyright

Copyright 2013–2014 Theo Hultberg/Iconara and contributors.

_Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License You may obtain a copy of the License at_

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

_Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License._
