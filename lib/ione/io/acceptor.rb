# encoding: utf-8


module Ione
  module Io
    # An acceptor wraps a server socket and accepts client connections.
    # @since v1.1.0
    class Acceptor
      # @private
      ServerSocket = RUBY_ENGINE == 'jruby' ? ::ServerSocket : Socket

      BINDING_STATE = 0
      CONNECTED_STATE = 1
      CLOSED_STATE = 2

      attr_reader :backlog

      # @private
      def initialize(host, port, backlog, unblocker, reactor, socket_impl=nil)
        @host = host
        @port = port
        @backlog = backlog
        @unblocker = unblocker
        @reactor = reactor
        @socket_impl = socket_impl || ServerSocket
        @accept_listeners = []
        @lock = Mutex.new
        @state = BINDING_STATE
        @closed_promise = Promise.new
        @bound_promise = Promise.new
      end

      # Register a listener to be notified when client connections are accepted
      #
      # @yieldparam [Ione::Io::ServerConnection] the connection to the client
      def on_accept(&listener)
        @lock.synchronize do
          @accept_listeners << listener
        end
      end

      # Register to receive a notification when the socket is closed, both for
      # expected and unexpected reasons.
      #
      # Errors raised by the callback will be ignored.
      #
      # @yield [error, nil] the error that caused the socket to close, or nil if
      #   the socket closed with #close
      def on_closed(&listener)
        @closed_promise.future.on_value { listener.call(nil) }
        @closed_promise.future.on_failure { |e| listener.call(e) }
      end

      def on_writable
      end

      def on_connected(&listener)
        @bound_promise.future.on_value { listener.call(nil) }
        @bound_promise.future.on_failure { |e| listener.call(e) }
      end

      # @private
      def bind
        addrinfos = @socket_impl.getaddrinfo(@host, @port, nil, Socket::SOCK_STREAM)
        begin
          _, port, _, ip, address_family, socket_type = addrinfos.shift
          @io = @socket_impl.new(address_family, socket_type, 0)
          bind_socket(@io, @socket_impl.sockaddr_in(port, ip), @backlog)
        rescue Errno::EADDRNOTAVAIL => e
          if addrinfos.empty?
            raise
          else
            retry
          end
        end
        @state = CONNECTED_STATE
        @bound_promise.fulfill(self)
        @bound_promise.future
      rescue => e
        close(e)
        @bound_promise.fail(e)
        @bound_promise.future
      end

      # Closes the socket and stops accepting connections
      #
      # @return [true, false] returns false if the socket was already closed
      def close(cause=nil)
        @lock.synchronize do
          return false if @state == CLOSED_STATE
          @state = CLOSED_STATE
        end
        if @io
          begin
            @io.close
            @io = nil
          rescue SystemCallError, IOError
            # nothing to do, the socket was most likely already closed
          end
        end
        if cause && !cause.is_a?(IoError)
          cause = ConnectionClosedError.new(cause.message)
        end
        if cause
          @closed_promise.fail(cause)
        else
          @closed_promise.fulfill(self)
        end
        true
      end

      # @private
      def to_io
        @io
      end

      # Returns true if the acceptor has stopped accepting connections
      def closed?
        @state == CLOSED_STATE
      end

      # Returns true if the acceptor is accepting connections
      def connected?
        @state != CLOSED_STATE
      end

      # @private
      def connecting?
        false
      end

      # @private
      def writable?
        false
      end

      # @private
      def read
        client_socket, host, port = accept
        connection = ServerConnection.new(client_socket, host, port, @unblocker)
        @reactor.accept(connection)
        notify_accept_listeners(connection)
      end

      if RUBY_ENGINE == 'jruby'
        # @private
        def bind_socket(socket, addr, backlog)
          socket.bind(addr, backlog)
        end
      else
        # @private
        def bind_socket(socket, addr, backlog)
          socket.bind(addr)
          socket.listen(backlog)
        end
      end

      private

      def accept
        client_socket, client_sockaddr = @io.accept_nonblock
        port, host = @socket_impl.unpack_sockaddr_in(client_sockaddr)
        return client_socket, host, port
      end

      def notify_accept_listeners(connection)
        listeners = @lock.synchronize { @accept_listeners }
        listeners.each { |l| l.call(connection) rescue nil }
      end
    end
  end
end
