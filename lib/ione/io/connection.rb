# encoding: utf-8

module Ione
  module Io
    # A wrapper around a socket. Handles connecting to the remote host, reading
    # from and writing to the socket.
    class Connection < BaseConnection
      attr_reader :connection_timeout

      # @private
      def initialize(host, port, connection_timeout, unblocker, clock, socket_impl=Socket)
        super(host, port)
        @connection_timeout = connection_timeout
        @unblocker = unblocker
        @clock = clock
        @socket_impl = socket_impl
        @lock = Mutex.new
        @write_buffer = ByteBuffer.new
        @connected_promise = Promise.new
        @closed_listener = method(:default_closed_listener)
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
          close(e) || default_closed_listener(e)
        end
        @connected_promise.future
      end

      def on_closed(&listener)
        @actual_closed_listener = listener
      end

      private

      def default_closed_listener(cause)
        if cause && !cause.is_a?(IoError)
          cause = ConnectionError.new(cause.message)
        end
        unless @connected_promise.future.completed?
          @connected_promise.fail(cause)
        end
        if @actual_closed_listener
          @actual_closed_listener.call(cause)
        end
      end
    end
  end
end