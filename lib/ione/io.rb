# encoding: utf-8

require 'socket'


module Ione
  CancelledError = Class.new(StandardError)
  IoError = Class.new(StandardError)

  module Io
    ConnectionError = Class.new(IoError)
    ConnectionClosedError = Class.new(ConnectionError)
    ConnectionTimeoutError = Class.new(ConnectionError)
  end
end

require 'ione/io/io_reactor'
require 'ione/io/base_connection'
require 'ione/io/connection'
require 'ione/io/server_connection'
require 'ione/io/ssl_connection'
require 'ione/io/acceptor'
