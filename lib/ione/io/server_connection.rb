# encoding: utf-8

module Ione
  module Io
    # @since v1.1.0
    class ServerConnection < BaseConnection
      # @private
      def initialize(socket, host, port, unblocker)
        super(host, port, unblocker)
        @io = socket
        @state = CONNECTED_STATE
      end

      def on_connected
        yield
      end
    end
  end
end
