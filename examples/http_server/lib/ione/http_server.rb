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
      @env_prototype = RACK_ENV_PROTOTYPE.dup
      @env_prototype['SERVER_NAME'] = Socket.gethostname
      @env_prototype['SERVER_PORT'] = @port
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
      HttpConnection.new(connection, @app, @env_prototype)
    end

    RACK_ENV_PROTOTYPE = {
      'REQUEST_METHOD' => nil,
      'SCRIPT_NAME' => ''.freeze,
      'PATH_INFO' => nil,
      'QUERY_STRING' => nil,
      'SERVER_NAME' => nil,
      'SERVER_PORT' => nil,
      'rack.version' => Rack::VERSION,
      'rack.url_scheme' => 'http',
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

  class HttpConnection
    def initialize(connection, app, env_prototype)
      @http_parser = Puma::HttpParser.new
      @app = app
      @env_prototype = env_prototype
      @connection = connection
      @connection.on_data(&method(:handle_data))
      @connection.on_closed(&method(:handle_closed))
    end

    def handle_data(data)
      env = @env_prototype.dup
      status = nil
      headers = nil
      body = nil
      begin
        consumed_bytes = @http_parser.execute(env, data, 0)
        env[PATH_INFO_KEY] = env[REQUEST_PATH_KEY]
        status, headers, body = @app.call(env)
      rescue => e
        status = 500
        headers = NO_HEADERS
        body = NO_BODY
      end
      respond(status, headers, body)
    end

    def respond(status, headers, body)
      buffer = ''
      begin
        buffer << "HTTP/1.1 #{status} #{STATUS_MESSAGES[status]}\r\n"
        headers.each do |header, value|
          buffer << "#{header}: #{value}\r\n"
        end
        sizeable_body = body.respond_to?(:size)
        body_size = sizeable_body && body.reduce(0) { |sum, part| sum + part.bytesize }
        if sizeable_body && body_size == 0
          buffer << CONTENT_LENGTH_ZERO
        elsif sizeable_body && body_size < 256
          buffer << "Content-Length: #{body_size}\r\n\r\n"
          body.each do |part|
            buffer << part
          end
        else
          buffer << CHUNKED_TRANSFER_ENCODING
          body.each do |part|
            chunk = part.to_s
            buffer << "#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n"
          end
          buffer << END_CHUNK
        end
      rescue
        buffer = "HTTP/1.1 500 #{STATUS_MESSAGES[500]}\r\n#{CONTENT_LENGTH_ZERO}"
      end
      @connection.write(buffer)
      @connection.drain
    end

    def handle_closed(cause=nil)
    end

    PATH_INFO_KEY = 'PATH_INFO'.freeze
    REQUEST_PATH_KEY = 'REQUEST_PATH'.freeze

    STATUS_MESSAGES = {
      200 => 'OK',
      404 => 'Not Found',
      500 => 'Internal Server Error',
    }.freeze

    CONTENT_LENGTH_ZERO = "Content-Length: 0\r\n\r\n".freeze
    CHUNKED_TRANSFER_ENCODING = "Transfer-Encoding: chunked\r\n\r\n".freeze
    END_CHUNK = "0\r\n\r\n".freeze
    NO_HEADERS = {}.freeze
    NO_BODY = [].freeze
  end
end
