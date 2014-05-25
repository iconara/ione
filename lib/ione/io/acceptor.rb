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
          @socket = @socket_impl.new(address_family, socket_type, 0)
          bind_socket(@socket, @socket_impl.sockaddr_in(port, ip), @backlog)
        rescue Errno::EADDRNOTAVAIL => e
          if addrinfos.empty?
            raise
          else
            retry
          end
        end
        Future.resolved(self)
      rescue => e
        Future.failed(e)
      end

      def close
        return false unless @socket
        begin
          @socket.close
        rescue SystemCallError, IOError
          # nothing to do, the socket was most likely already closed
        end
        @socket = nil
        true
      end

      def to_io
        @socket
      end

      def closed?
        @socket.nil?
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
        client_socket, client_sockaddr = @socket.accept_nonblock
        port, host = @socket_impl.unpack_sockaddr_in(client_sockaddr)
        connection = ServerConnection.new(client_socket, host, port, @unblocker)
        @reactor.accept(connection)
        listeners = @lock.synchronize { @accept_listeners }
        listeners.each { |l| l.call(connection) rescue nil }
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
    end
  end
end
