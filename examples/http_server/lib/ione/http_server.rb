# encoding: utf-8

require 'ione'
require 'ione/http_client'
require 'puma/puma_http11'
require 'rack'


module Ione
  class HttpServer
    def initialize(port, app)
      @port = port
      @app = app
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
      HttpConnection.new(connection, @app)
    end
  end

  class HttpConnection
    def initialize(connection, app)
      @http_parser = Puma::HttpParser.new
      @app = app
      @connection = connection
      @connection.on_data(&method(:handle_data))
      @connection.on_closed(&method(:handle_closed))
    end

    def handle_data(data)
      env = RACK_ENV_PROTOTYPE.dup
      consumed_bytes = @http_parser.execute(env, data, 0)
      status, headers, body = @app.call(env)
      @connection.write do |buffer|
        buffer << "HTTP/1.1 200 OK\r\n"
        headers.each do |header, value|
          buffer << "#{header}: #{value}\r\n"
        end
        buffer << "Transfer-Encoding: chunked\r\n"
        buffer << "\r\n"
        body.each do |part|
          chunk = part.to_s
          buffer << "#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n"
        end
        buffer << "0\r\n\r\n"
      end
      @connection.drain
    end

    def handle_closed(cause=nil)
    end

    RACK_ENV_PROTOTYPE = {
      'REQUEST_METHOD' => nil,
      'SCRIPT_NAME' => nil,
      'PATH_INFO' => nil,
      'QUERY_STRING' => nil,
      'SERVER_NAME' => nil,
      'SERVER_PORT' => nil,
      'rack.version' => Rack::VERSION,
      'rack.url_scheme' => nil,
      'rack.input' => nil,
      'rack.errors' => nil,
      'rack.multithread' => true,
      'rack.multiprocess' => false,
      'rack.run_once' => false,
      'rack.hijack?' => false,
      'rack.hijack' => nil,
      'rack.hijack_io' => nil,
    }.freeze
  end
end
