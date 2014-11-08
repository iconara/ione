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
      @responses = []
    end

    def connect
      f = @reactor.start
      f = f.flat_map { @reactor.connect(@host, @port) }
      f.on_value do |connection|
        @connection = connection
        process_responses(connection.to_stream)
      end
      f.map(self)
    end

    def process_responses(byte_stream)
      line_stream = byte_stream.aggregate(Ione::ByteBuffer.new) do |data, downstream, buffer|
        buffer << data
        while (newline_index = buffer.index("\r\n"))
          line = buffer.read(newline_index + 2)
          line.chomp!
          downstream << line
        end
        buffer
      end
      response_stream = line_stream.aggregate(RedisProtocol::BaseState.new) do |line, downstream, state|
        state = state.feed_line(line)
        if state.response?
          downstream << [state.response, state.error?]
        end
        state
      end
      response_stream.each do |response, error|
        promise = @responses.shift
        if error
          promise.fail(StandardError.new(response))
        else
          promise.fulfill(response)
        end
      end
      self
    end

    def method_missing(*args)
      promise = Ione::Promise.new
      @responses << promise
      request = "*#{args.size}\r\n"
      args.each do |arg|
        arg_str = arg.to_s
        request << "$#{arg_str.bytesize}\r\n#{arg_str}\r\n"
      end
      @connection.write(request)
      promise.future
    end

    module RedisProtocol
      class State
        attr_reader :next_state

        def initialize
          @next_state = self
        end

        def response?
          false
        end

        def continue(next_state=self)
          next_state
        end

        def complete(response, error=false)
          CompleteState.new(response, error)
        end
      end

      class BulkState < State
        def feed_line(line)
          complete(line)
        end
      end

      class MultiBulkState < State
        def initialize(size)
          super()
          @size = size
          @elements = []
        end

        def feed_line(line)
          if line.start_with?('$')
            line.slice!(0, 1)
            if line.to_i == -1
              @elements << nil
            end
          else
            @elements << line
          end
          if @elements.size == @size
            complete(@elements)
          else
            continue
          end
        end
      end

      class BaseState < State
        def feed_line(line)
          first_char = line.slice!(0, 1)
          case first_char
          when '+' then complete(line)
          when ':' then complete(line.to_i)
          when '-' then complete(line, true)
          when '$'
            if line.to_i == -1
              complete(nil)
            else
              continue(BulkState.new)
            end
          when '*'
            continue(MultiBulkState.new(line.to_i))
          else
            continue
          end
        end
      end

      class CompleteState < BaseState
        attr_reader :response

        def initialize(response, error=false)
          @response = response
          @error = error
        end

        def response?
          true
        end

        def error?
          @error
        end
      end
    end
  end
end
