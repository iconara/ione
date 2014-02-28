# encoding: utf-8

module Ione
  CancelledError = Class.new(StandardError)
  IoError = Class.new(StandardError)

  module Io
    ConnectionError = Class.new(IoError)
    ConnectionClosedError = Class.new(ConnectionError)
    ConnectionTimeoutError = Class.new(ConnectionError)
  end
end

require 'cql/io/io_reactor'
require 'cql/io/connection'
