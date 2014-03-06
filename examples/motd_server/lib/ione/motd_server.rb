# encoding: utf-8

require 'ione'


module Ione
  class MotdServer
    def initialize(port, path='/etc/motd')
      @port = port
      @path = path
      @reactor = Io::IoReactor.new
    end

    def start
      f = @reactor.start
      f = f.flat_map do
        @reactor.bind('0.0.0.0', @port, 5) do |acceptor|
          acceptor.on_accept do |connection|
            accept_connection(connection)
          end
        end
      end
      f.map(self)
    end

    def stop
      @reactor.stop.map(self)
    end

    private

    def accept_connection(connection)
      connection.write(File.read(@path))
      @reactor.schedule_timer(0.01).on_value do
        connection.close
      end
    end
  end
end
