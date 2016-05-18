# encoding: utf-8

module Ione
  module Io
    # @private
    class SslServerConnection < ServerConnection
      ACCEPTING_STATE = 0
      ESTABLISHED_STATE = 1

      def initialize(socket, host, port, unblocker, thread_pool, ssl_context, accept_callback, ssl_socket_impl=nil)
        super(socket, host, port, unblocker, thread_pool)
        @ssl_context = ssl_context
        @accept_callback = accept_callback
        @ssl_socket_impl = ssl_socket_impl || OpenSSL::SSL::SSLSocket
        @ssl_state = ACCEPTING_STATE
      end

      # @private
      def to_io
        if @ssl_state == ESTABLISHED_STATE
          @io.to_io
        else
          @io
        end
      end

      def read
        if @ssl_state == ACCEPTING_STATE
          begin
            @ssl_io ||= @ssl_socket_impl.new(@io, @ssl_context)
            @ssl_io.accept_nonblock
            @io = @ssl_io
            @ssl_state = ESTABLISHED_STATE
            @accept_callback.call(self)
          rescue IO::WaitReadable
            # connection not ready yet
          rescue => e
            close(e)
          end
        else
          super
        end
      end
    end
  end
end
