# encoding: utf-8

module Ione
  module Io
    class ServerConnection < BaseConnection
      # @private
      def initialize(socket, host, port, unblocker)
        super(host, port, unblocker)
        @io = socket
        @state = :connected
      end
    end
  end
end
