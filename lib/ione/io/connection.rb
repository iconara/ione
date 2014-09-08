# encoding: utf-8

module Ione
  module Io
    # A wrapper around a socket. Handles connecting to the remote host, reading
    # from and writing to the socket.
    class Connection < BaseConnection
      attr_reader :connection_timeout

      # @private
      def initialize(host, port, connection_timeout, unblocker, clock, socket_impl=Socket)
        super(host, port, unblocker)
        @connection_timeout = connection_timeout
        @clock = clock
        @socket_impl = socket_impl
        @connected_promise = Promise.new
        on_closed(&method(:cleanup_on_close))
      end

      # @private
      def connect
        begin
          unless @addrinfos
            @connection_started_at = @clock.now
            @addrinfos = @socket_impl.getaddrinfo(@host, @port, nil, Socket::SOCK_STREAM)
          end
          unless @io
            _, port, _, ip, address_family, socket_type = @addrinfos.shift
            @sockaddr = @socket_impl.sockaddr_in(port, ip)
            @io = @socket_impl.new(address_family, socket_type, 0)
          end
          unless connected?
            @io.connect_nonblock(@sockaddr)
            @state = :connected
            @connected_promise.fulfill(self)
          end
        rescue Errno::EISCONN
          @state = :connected
          @connected_promise.fulfill(self)
        rescue Errno::EINPROGRESS, Errno::EALREADY
          if @clock.now - @connection_started_at > @connection_timeout
            close(ConnectionTimeoutError.new("Could not connect to #{@host}:#{@port} within #{@connection_timeout}s"))
          end
        rescue Errno::EINVAL, Errno::ECONNREFUSED => e
          if @addrinfos.empty?
            close(e)
          else
            @io = nil
            retry
          end
        rescue SystemCallError => e
          close(e)
        rescue SocketError => e
          close(e) || cleanup_on_close(e)
        end
        @connected_promise.future
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