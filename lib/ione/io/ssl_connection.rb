# encoding: utf-8

require 'openssl'


module Ione
  module Io
    # @private
    class SslConnection < BaseConnection
      def initialize(host, port, io, unblocker, ssl_context=nil, socket_impl=OpenSSL::SSL::SSLSocket)
        super(host, port, unblocker)
        @socket_impl = socket_impl
        @ssl_context = ssl_context
        @raw_io = io
        @connected_promise = Promise.new
        on_closed(&method(:cleanup_on_close))
      end

      def connect
        if @io.nil? && @ssl_context
          @io = @socket_impl.new(@raw_io, @ssl_context)
        elsif @io.nil?
          @io = @socket_impl.new(@raw_io)
        end
        @io.connect_nonblock
        @state = CONNECTED_STATE
        @connected_promise.fulfill(self)
        @connected_promise.future
      rescue IO::WaitReadable, IO::WaitWritable
        # WaitReadable in JRuby, WaitWritable in MRI
        @connected_promise.future
      rescue => e
        close(e)
        @connected_promise.future
      end

      def to_io
        @raw_io
      end

      if RUBY_ENGINE == 'jruby'
        # @private
        def read
          while true
            @data_stream << @io.read_nonblock(2**16)
          end
        rescue IO::WaitReadable, IO::WaitWritable
          # no more data available
        rescue => e
          close(e)
        end
      else
        # @private
        def read
          read_size = 2**16
          while read_size > 0
            @data_stream << @io.read_nonblock(read_size)
            read_size = @io.pending
          end
        rescue IO::WaitReadable, IO::WaitWritable
          # no more data available
        rescue => e
          close(e)
        end
      end

      private

      def cleanup_on_close(cause)
        if cause && !cause.is_a?(IoError)
          cause = ConnectionError.new(cause.message)
        end
        unless @connected_promise.future.completed?
          @connected_promise.fail(cause)
        end
      end
    end
  end
end
