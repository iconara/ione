# encoding: utf-8

require 'ione'


module Ione
  class RedisClient
    def self.connect(host, port)
      new(host, port).connect
    end
    
    def initialize(host, port)
      @host = host
      @port = port
      @reactor = Ione::Io::IoReactor.new
    end
    
    def connect
      f = @reactor.start
      f = f.flat_map do
        @reactor.connect(@host, @port, 1) { |connection| RedisProtocolHandler.new(connection) }
      end
      f.on_value do |protocol_handler|
        @protocol_handler = protocol_handler
      end
      f.map(self)
    end

    def method_missing(name, *args)
      @protocol_handler.send_request(name, *args)
    end
  end

  class LineProtocolHandler
    def initialize(connection)
      @connection = connection
      @connection.on_data(&method(:process_data))
      @buffer = Ione::ByteBuffer.new
      @requests = []
    end

    def on_line(&listener)
      @line_listener = listener
    end

    def write(command_string)
      @connection.write(command_string)
    end

    def process_data(new_data)
      lines = []
      @buffer << new_data
      while (newline_index = @buffer.index("\r\n"))
        line = @buffer.read(newline_index + 2)
        line.chomp!
        lines << line
      end
      lines.each do |line|
        @line_listener.call(line) if @line_listener
      end
    end
  end

  class RedisProtocolHandler
    def initialize(connection)
      @line_protocol = LineProtocolHandler.new(connection)
      @line_protocol.on_line(&method(:handle_line))
      @responses = []
      @state = BaseState.new(method(:handle_response))
    end

    def send_request(*args)
      promise = Ione::Promise.new
      @responses << promise
      request = "*#{args.size}\r\n"
      args.each do |arg|
        arg_str = arg.to_s
        request << "$#{arg_str.bytesize}\r\n#{arg_str}\r\n"
      end
      @line_protocol.write(request)
      promise.future
    end

    def handle_response(result, error=false)
      promise = @responses.shift
      if error
        promise.fail(StandardError.new(result))
      else
        promise.fulfill(result)
      end
    end

    def handle_line(line)
      @state = @state.handle_line(line)
    end

    class State
      def initialize(result_handler)
        @result_handler = result_handler
      end

      def complete!(result)
        @result_handler.call(result)
      end

      def fail!(message)
        @result_handler.call(message, true)
      end
    end

    class BulkState < State
      def handle_line(line)
        complete!(line)
        BaseState.new(@result_handler)
      end
    end

    class MultiBulkState < State
      def initialize(result_handler, expected_elements)
        super(result_handler)
        @expected_elements = expected_elements
        @elements = []
      end

      def handle_line(line)
        if line.start_with?('$')
          line.slice!(0, 1)
          if line.to_i == -1
            @elements << nil
          end
        else
          @elements << line
        end
        if @elements.size == @expected_elements
          complete!(@elements)
          BaseState.new(@result_handler)
        else
          self
        end
      end
    end

    class BaseState < State
      def handle_line(line)
        next_state = self
        first_char = line.slice!(0, 1)
        case first_char
        when '+' then complete!(line)
        when ':' then complete!(line.to_i)
        when '-' then fail!(line)
        when '$'
          if line.to_i == -1
            complete!(nil)
          else
            next_state = BulkState.new(@result_handler)
          end
        when '*'
          next_state = MultiBulkState.new(@result_handler, line.to_i)
        end
        next_state
      end
    end
  end
end
