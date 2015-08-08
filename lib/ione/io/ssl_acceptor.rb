# encoding: utf-8


module Ione
  module Io
    # @private
    class SslAcceptor < Acceptor
      def initialize(host, port, backlog, unblocker, thread_pool, reactor, ssl_context, socket_impl=nil, ssl_socket_impl=nil)
        super(host, port, backlog, unblocker, thread_pool, reactor, socket_impl)
        @ssl_context = ssl_context
        @ssl_socket_impl = ssl_socket_impl
      end

      def read
        client_socket, host, port = accept
        connection = SslServerConnection.new(client_socket, host, port, @unblocker, @thread_pool, @ssl_context, method(:notify_accept_listeners), @ssl_socket_impl)
        @reactor.accept(connection)
      end
    end
  end
end
