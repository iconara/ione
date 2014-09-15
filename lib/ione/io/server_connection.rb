# encoding: utf-8

module Ione
  module Io
    class ServerConnection < BaseConnection
      # @private
      def initialize(socket, host, port, unblocker)
        super(host, port)
        @io = socket
        @unblocker = unblocker
        @write_buffer = ByteBuffer.new
        @state = :connected
      end
    end
  end
end
