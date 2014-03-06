# encoding: utf-8

module Ione
  module Io
    class ServerConnection < BaseConnection
      attr_reader :host, :port

      # @private
      def initialize(socket, host, port, unblocker)
        @io = socket
        @host = host
        @port = port
        @unblocker = unblocker
        @lock = Mutex.new
        @write_buffer = ByteBuffer.new
        @connected = true
      end
    end
  end
end
