# encoding: utf-8


module Ione
  module Io
    class Acceptor
      ServerSocket = RUBY_ENGINE == 'jruby' ? ::ServerSocket : Socket

      attr_reader :backlog

      def initialize(host, port, backlog, unblocker, reactor, socket_impl=nil)
        @host = host
        @port = port
        @backlog = backlog
        @unblocker = unblocker
        @reactor = reactor
        @socket_impl = socket_impl || ServerSocket
        @accept_listeners = []
        @lock = Mutex.new
      end

      def on_accept(&listener)
        @lock.synchronize do
          @accept_listeners << listener
        end
      end

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
        Future.resolved(self)
      rescue => e
        close
        Future.failed(e)
      end

      def close
        return false unless @io
        begin
          @io.close
        rescue SystemCallError, IOError
          # nothing to do, the socket was most likely already closed
        end
        @io = nil
        true
      end

      def to_io
        @io
      end

      def closed?
        @io.nil?
      end

      def connected?
        !closed?
      end

      def connecting?
        false
      end

      def writable?
        false
      end

      def read
        client_socket, host, port = accept
        connection = ServerConnection.new(client_socket, host, port, @unblocker)
        @reactor.accept(connection)
        notify_accept_listeners(connection)
      end

      if RUBY_ENGINE == 'jruby'
        def bind_socket(socket, addr, backlog)
          socket.bind(addr, backlog)
        end
      else
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
