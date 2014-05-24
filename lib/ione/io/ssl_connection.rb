# encoding: utf-8

require 'openssl'


module Ione
  module Io
    class SslConnection < BaseConnection
      def initialize(host, port, io, unblocker, ssl_context=nil, socket_impl=OpenSSL::SSL::SSLSocket)
        super(host, port, unblocker)
        @socket_impl = socket_impl
        @ssl_context = ssl_context
        @raw_io = io
        @connected_promise = Promise.new
      end

      def connect
        if @io.nil? && @ssl_context
          @io = @socket_impl.new(@raw_io, @ssl_context)
        elsif @io.nil?
          @io = @socket_impl.new(@raw_io)
        end
        @io.connect_nonblock
        @state = :connected
        @connected_promise.fulfill(self)
        @connected_promise.future
      rescue OpenSSL::SSL::SSLError => e
        unless e.message.include?(WOULD_BLOCK_MESSAGE)
          @connected_promise.fail(e)
        end
        @connected_promise.future
      end

      def to_io
        @raw_io
      end

      if RUBY_ENGINE == 'jruby'
        # @private
        def read
          while true
            new_data = @io.read_nonblock(2**16)
            @data_listener.call(new_data) if @data_listener
          end
        rescue OpenSSL::SSL::SSLErrorWaitReadable
          # no more data available
        rescue => e
          close(e)
        end
      else
        # @private
        def read
          read_size = 2**16
          while read_size > 0
            new_data = @io.read_nonblock(read_size)
            @data_listener.call(new_data) if @data_listener
            read_size = @io.pending
          end
        rescue => e
          close(e)
        end
      end

      private

      WOULD_BLOCK_MESSAGE = 'would block'.freeze
    end
  end
end
