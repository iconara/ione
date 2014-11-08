# encoding: utf-8

require 'ione'


module Ione
  RedisError = Class.new(StandardError)

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
        process_data_chunks(connection.to_stream)
      end
      f.map(self)
    end

    def process_data_chunks(data_chunk_stream)
      line_stream = data_chunk_stream.aggregate(Ione::ByteBuffer.new) do |data, downstream, buffer|
        buffer << data
        while (newline_index = buffer.index("\r\n"))
          line = buffer.read(newline_index + 2)
          line.chomp!
          downstream << line
        end
        buffer
      end
      process_lines(line_stream)
    end

    def process_lines(line_stream)
      response_stream = line_stream.aggregate(RedisProtocol::BaseState.new) do |line, downstream, state|
        state = state.feed_line(line)
        if state.response?
          downstream << [state.response, state.error?]
        end
        state
      end
      process_responses(response_stream)
    end

    def process_responses(response_stream)
      response_stream.each do |response, error|
        promise = @responses.shift
        if error
          promise.fail(RedisError.new(response))
        else
          promise.fulfill(response)
        end
      end
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

    # This is an implementation of the Redis protocol as a state machine.
    #
    # You start with {BaseState} and call {#feed_line} with a line received
    # from Redis. {#feed_line} will return a new state object, on which you
    # should call {#feed_line} with the next line from Redis.
    #
    # The state objects returned by {#feed_line} represent either a complete or
    # a partial response. You can check if a state represents a complete
    # response by calling {#response?}. If this method returns true you can call
    # {#response} to get the response (which is either a string or an array of
    # strings). In some cases the response is an error, in which case {#error?}
    # will return true, and {#response} will return the error message.
    #
    # The state that represents a complete response also works like the base
    # state so you can feed it a line to start processing the next response.
    module RedisProtocol
      class State
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
