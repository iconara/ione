# encoding: utf-8

require 'ione/heap'


module Ione
  module Io
    ReactorError = Class.new(IoError)

    # An IO reactor takes care of all the IO for a client. It handles opening
    # new connections, and making sure that connections that have data to send
    # flush to the network, and connections that have data coming in read that
    # data and delegate it to their protocol handlers.
    #
    # All IO is done in a single background thread, regardless of how many
    # connections you open. There shouldn't be any problems handling hundreds of
    # connections if needed. All operations are thread safe, but you should take
    # great care when in your protocol handlers to make sure that they don't
    # do too much work in their data handling callbacks, since those will be
    # run in the reactor thread, and every cycle you use there is a cycle which
    # can't be used to handle IO.
    #
    # The IO reactor is completely protocol agnostic, and it's up to you to
    # create objects that can interpret the bytes received from remote hosts,
    # and to send the correct commands back. The way this works is that when you
    # open a connection you can provide a protocol handler factory as a block,
    # (or you can simply wrap the returned connection). This factory can be used
    # to create objects that wrap the raw connections and register to receive
    # new data, and it can write data to connection. It can also register to be
    # notified when the socket is closed, or it can itself close the socket.
    #
    # @example A protocol handler that processes whole lines
    #   io_reactor.connect('example.com', 6543, 10) do |connection|
    #     LineProtocolHandler.new(connection)
    #   end
    #
    #   # ...
    #
    #   class LineProtocolHandler
    #     def initialize(connection)
    #       @connection = connection
    #       # register a listener method for new data, this must be done in the
    #       # in the constructor, and only one listener can be registered
    #       @connection.on_data(&method(:process_data))
    #       @buffer = ''
    #     end
    #
    #     def process_data(new_data)
    #       # in this fictional protocol we want to process whole lines, so we
    #       # append new data to our buffer and then loop as long as there is
    #       # a newline in the buffer, everything up until a newline is a
    #       # complete line
    #       @buffer << new_data
    #       while newline_index = @buffer.index("\n")
    #         line = @buffer.slice!(0, newline_index + 1)
    #         line.chomp!
    #         # Now do something interesting with the line, but remember that
    #         # while you're in the data listener method you're executing in the
    #         # IO reactor thread so you're blocking the reactor from doing
    #         # other IO work. You should not do any heavy lifting here, but
    #         # instead hand off the data to your application's other threads.
    #         # One way of doing that is to create a Ione::Future in the method
    #         # that sends the request, and then complete the future in this
    #         # method. How you keep track of which future belongs to which
    #         # reply is very protocol dependent so you'll have to figure that
    #         # out yourself.
    #       end
    #     end
    #
    #     def send_request(command_string)
    #       # This example primarily shows how to implement a data listener
    #       # method, but this is how you write data to the connection. The
    #       # method can be called anything, it doesn't have to be #send_request
    #       @connection.write(command_string)
    #       # The connection object itself is threadsafe, but to create any
    #       # interesting protocol you probably need to set up some state for
    #       # each request so that you know which request to complete when you
    #       # get data back.
    #     end
    #   end
    #
    # @since v1.0.0
    class IoReactor
      # Initializes a new IO reactor.
      #
      # @param options [Hash] only used to inject behaviour during tests
      def initialize(options={})
        @clock = options[:clock] || Time
        @unblocker = Unblocker.new
        @io_loop = IoLoopBody.new(options)
        @io_loop.add_socket(@unblocker)
        @scheduler = Scheduler.new
        @running = false
        @stopped = false
        @started_promise = Promise.new
        @stopped_promise = Promise.new
        @lock = Mutex.new
      end

      # Register to receive notifications when the reactor shuts down because
      # of an irrecoverable error.
      #
      # The listener block will be called in the reactor thread. Any errors that
      # it raises will be ignored.
      #
      # @yield [error] the error that cause the reactor to stop
      def on_error(&listener)
        @stopped_promise.future.on_failure(&listener)
      end

      # Returns true as long as the reactor is running. It will be true even
      # after {#stop} has been called, but false when the future returned by
      # {#stop} completes.
      def running?
        @running
      end

      # Starts the reactor. This will spawn a background thread that will manage
      # all connections.
      #
      # This method is asynchronous and returns a future which completes when
      # the reactor has started.
      #
      # @return [Ione::Future] a future that will resolve to the reactor itself
      def start
        @lock.synchronize do
          raise ReactorError, 'Cannot start a stopped IO reactor' if @stopped
          return @started_promise.future if @running
          @running = true
        end
        Thread.start do
          @started_promise.fulfill(self)
          begin
            until @stopped
              @io_loop.tick
              @scheduler.tick
            end
          ensure
            @io_loop.close_sockets
            @scheduler.cancel_timers
            @running = false
            if $!
              @stopped_promise.fail($!)
            else
              @stopped_promise.fulfill(self)
            end
          end
        end
        @started_promise.future
      end

      # Stops the reactor.
      #
      # This method is asynchronous and returns a future which completes when
      # the reactor has completely stopped, or fails with an error if the reactor
      # stops or has already stopped because of a failure.
      #
      # @return [Ione::Future] a future that will resolve to the reactor itself
      def stop
        @stopped = true
        @unblocker.unblock
        @stopped_promise.future
      end

      # Opens a connection to the specified host and port.
      #
      # @example A naive HTTP client
      #   connection_future = reactor.connect('example.com', 80)
      #   connection_future.on_value do |connection|
      #     connection.write("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")
      #     connection.on_data do |data|
      #       print(data)
      #     end
      #   end
      #
      # @param host [String] the host to connect to
      # @param port [Integer] the port to connect to
      # @param options [Hash, Numeric] a hash of options (see below)
      #   or the connection timeout (equivalent to using the `:timeout` option).
      # @option options [Numeric] :timeout (5) the number of seconds
      #   to wait for a connection before failing
      # @option options [Boolean, OpenSSL::SSL::SSLContext] :ssl (false)
      #   pass an `OpenSSL::SSL::SSLContext` to upgrade the connection to SSL,
      #   or true to upgrade the connection and create a new context.
      # @yieldparam [Ione::Io::Connection] connection the newly opened connection
      # @return [Ione::Future] a future that will resolve when the connection is
      #   open. The value will be the connection, or when a block is given the
      #   value returned by the block.
      def connect(host, port, options=nil, &block)
        if options.is_a?(Numeric) || options.nil?
          timeout = options || 5
          ssl = false
        elsif options
          timeout = options[:timeout] || 5
          ssl = options[:ssl]
        end
        connection = Connection.new(host, port, timeout, @unblocker, @clock)
        f = connection.connect
        @io_loop.add_socket(connection)
        @unblocker.unblock
        if ssl
          f = f.flat_map do
            ssl_context = ssl == true ? nil : ssl
            upgraded_connection = SslConnection.new(host, port, connection.to_io, @unblocker, ssl_context)
            ff = upgraded_connection.connect
            @io_loop.remove_socket(connection)
            @io_loop.add_socket(upgraded_connection)
            @unblocker.unblock
            ff
          end
        end
        f = f.map(&block) if block_given?
        f
      end

      # Starts a server bound to the specified host and port.
      #
      # A server is represented by an {Acceptor}, which wraps the server socket
      # and accepts client connections. By registering to be notified on new
      # connections, via {Acceptor#on_accept}, you can attach your server
      # handling code to a connection.
      #
      # @example An echo server
      #   acceptor_future = reactor.bind('0.0.0.0', 11111)
      #   acceptor_future.on_value do |acceptor|
      #     acceptor.on_accept do |connection|
      #       connection.on_data do |data|
      #         connection.write(data)
      #       end
      #     end
      #   end
      #
      # @example A more realistic server template
      #   class EchoServer
      #     def initialize(acceptor)
      #       @acceptor = acceptor
      #       @acceptor.on_accept do |connection|
      #         handle_connection(connection)
      #       end
      #     end
      #
      #     def handle_connection(connection)
      #       connection.on_data do |data|
      #         connection.write(data)
      #       end
      #     end
      #   end
      #
      #   server_future = reactor.bind('0.0.0.0', 11111) do |acceptor|
      #     EchoServer.new(acceptor)
      #   end
      #
      #   server_future.on_value do |echo_server|
      #     # this is called when the server has started
      #   end
      #
      # @param host [String] the host to bind to, for example 127.0.0.1,
      #   'example.com' – or '0.0.0.0' to bind to all interfaces
      # @param port [Integer] the port to bind to
      # @param options [Hash]
      # @option options [Integer] :backlog (5) the maximum number of pending
      #   (unaccepted) connections, i.e. Socket::SOMAXCONN
      # @option options [OpenSSL::SSL::SSLContext] :ssl (nil) when specified the
      #   server will use this SSLContext to encrypt connections
      # @yieldparam [Ione::Io::Acceptor] the acceptor instance for this server
      # @return [Ione::Future] a future that will resolve when the server is
      #   bound. The value will be the acceptor, or when a block is given, the
      #   value returned by the block.
      # @since v1.1.0
      def bind(host, port, options=nil, &block)
        if options.is_a?(Integer) || options.nil?
          backlog = options || 5
          ssl_context = nil
        elsif options
          backlog = options[:backlog] || 5
          ssl_context = options[:ssl]
        end
        if ssl_context
          server = SslAcceptor.new(host, port, backlog, @unblocker, self, ssl_context)
        else
          server = Acceptor.new(host, port, backlog, @unblocker, self)
        end
        f = server.bind
        @io_loop.add_socket(server)
        @unblocker.unblock
        f = f.map(&block) if block_given?
        f
      end

      # @private
      def accept(socket)
        @io_loop.add_socket(socket)
        @unblocker.unblock
      end

      # Returns a future that completes after the specified number of seconds.
      #
      # @param timeout [Float] the number of seconds to wait until the returned
      #   future is completed
      # @return [Ione::Future] a future that completes when the timer expires
      def schedule_timer(timeout)
        @scheduler.schedule_timer(timeout)
      end

      # Cancels a previously scheduled timer.
      #
      # The timer will fail with a {Ione::CancelledError}.
      #
      # @param timer_future [Ione::Future] the future returned by {#schedule_timer}
      # @since v1.1.3
      def cancel_timer(timer_future)
        @scheduler.cancel_timer(timer_future)
      end

      def to_s
        @io_loop.to_s
      end
    end

    # @private
    class Unblocker
      def initialize
        @out, @in = IO.pipe
        @lock = Mutex.new
        @state = :open
        @writables = [@in]
      end

      def connected?
        true
      end

      def connecting?
        false
      end

      def writable?
        false
      end

      def closed?
        @state == :closed
      end

      def unblock
        if @state != :closed
          @lock.lock
          begin
            if @state != :closed && IO.select(nil, @writables, nil, 0)
              @in.write_nonblock(PING_BYTE)
            end
          ensure
            @lock.unlock
          end
        end
      end

      def read
        @lock.lock
        if @state != :closed
          @out.read_nonblock(65536)
        end
      ensure
        @lock.unlock
      end

      def close
        @lock.synchronize do
          return if @state == :closed
          @state = :closed
        end
        @in.close
        @out.close
        @in = nil
        @out = nil
      end

      def to_io
        @out
      end

      def to_s
        %(#<#{self.class.name}>)
      end

      private

      PING_BYTE = "\0".freeze
    end

    # @private
    class Timer < Promise
      include Comparable

      attr_reader :time

      def initialize(time)
        super()
        @time = time
      end

      def <=>(other)
        cmp = @time <=> other.time
        if cmp == 0
          self.object_id <=> other.object_id
        else
          cmp
        end
      end

      def to_s
        "#<#{self.class.name}:#{object_id} @time=#{@time.to_f}>"
      end
      alias_method :inspect, :to_s
    end

    # @private
    class IoLoopBody
      def initialize(options={})
        @selector = options[:selector] || IO
        @clock = options[:clock] || Time
        @timeout = options[:tick_resolution] || 1
        @lock = Mutex.new
        @sockets = []
      end

      def add_socket(socket)
        @lock.lock
        sockets = @sockets.reject { |s| s.closed? }
        sockets << socket
        @sockets = sockets
      ensure
        @lock.unlock
      end

      def remove_socket(socket)
        @lock.synchronize do
          @sockets = @sockets.reject { |s| s == socket || s.closed? }
        end
      end

      def close_sockets
        @sockets.each do |s|
          begin
            s.close
          rescue
            # the socket had most likely already closed due to an error
          end
        end
      end

      def tick
        readables = []
        writables = []
        connecting = []
        @sockets.each do |s|
          if s.connected?
            readables << s
          elsif s.connecting?
            connecting << s
          end
          if s.connecting? || s.writable?
            writables << s
          end
        end
        begin
          r, w, _ = @selector.select(readables, writables, nil, @timeout)
          connecting.each { |s| s.connect }
          r && r.each { |s| s.read }
          w && w.each { |s| s.flush }
        rescue IOError, Errno::EBADF
        end
      end

      def to_s
        %(#<#{IoReactor.name} @connections=[#{@sockets.map(&:to_s).join(', ')}]>)
      end
    end

    # @private
    class Scheduler
      def initialize(options={})
        @clock = options[:clock] || Time
        @lock = Mutex.new
        @timer_queue = Heap.new
        @pending_timers = {}
      end

      def schedule_timer(timeout)
        @lock.lock
        timer = Timer.new(@clock.now + timeout)
        @timer_queue << timer
        @pending_timers[timer.future] = timer
        timer.future
      ensure
        @lock.unlock
      end

      def cancel_timer(timer_future)
        timer = nil
        @lock.lock
        begin
          if (timer = @pending_timers.delete(timer_future))
            @timer_queue.delete(timer)
          end
        ensure
          @lock.unlock
        end
        if timer
          timer.fail(CancelledError.new)
        end
      end

      def cancel_timers
        timers = []
        @lock.lock
        begin
          while (timer = @timer_queue.pop)
            @pending_timers.delete(timer.future)
            timers << timer
          end
        ensure
          @lock.unlock
        end
        timers.each do |timer|
          timer.fail(CancelledError.new)
        end
      end

      def tick
        unless @timer_queue.empty?
          now = @clock.now
          first_timer = @timer_queue.peek
          if first_timer && first_timer.time <= now
            expired_timers = []
            @lock.lock
            begin
              while (timer = @timer_queue.peek) && timer.time <= now
                @timer_queue.pop
                @pending_timers.delete(timer.future)
                expired_timers << timer
              end
            ensure
              @lock.unlock
            end
            expired_timers.each do |timer|
              timer.fulfill
            end
          end
        end
      end

      def to_s
        %(#<#{self.class.name} @timers=[#{@pending_timers.values.map(&:to_s).join(', ')}]>)
      end
    end
  end
end