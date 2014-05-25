# encoding: utf-8

module Ione
  module Io
    # @private
    class SslServerConnection < ServerConnection
      def initialize(socket, host, port, unblocker, ssl_context, accept_callback, ssl_socket_impl=nil)
        super(socket, host, port, unblocker)
        @ssl_context = ssl_context
        @accept_callback = accept_callback
        @ssl_socket_impl = ssl_socket_impl || OpenSSL::SSL::SSLSocket
        @ssl_state = :accepting
      end

      # @private
      def to_io
        if @ssl_state == :established
          @io.to_io
        else
          @io
        end
      end

      def read
        if @ssl_state == :accepting
          begin
            @ssl_io ||= @ssl_socket_impl.new(@io, @ssl_context)
            @ssl_io.accept_nonblock
            @io = @ssl_io
            @ssl_state = :established
            @accept_callback.call(self)
          rescue OpenSSL::SSL::SSLError => e
            unless e.message.include?(WOULD_BLOCK_MESSAGE)
              close(e)
            end
          rescue => e
            close(e)
          end
        else
          super
        end
      end

      private

      WOULD_BLOCK_MESSAGE = 'would block'.freeze
    end
  end
end
