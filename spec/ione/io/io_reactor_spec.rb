# encoding: utf-8

require 'spec_helper'


module Ione
  module Io
    describe IoReactor do
      let :reactor do
        described_class.new(options)
      end

      let :options do
        {selector: selector, clock: clock, drain_timeout: 3}
      end

      let! :selector do
        IoReactorSpec::FakeSelector.new
      end

      let :clock do
        double(:clock, now: 0)
      end

      shared_context 'running_reactor' do
        before do
          selector.handler do |readables, writables, _, _|
            writables.each do |writable|
              fake_connected(writable)
            end
            [[], writables, []]
          end
        end

        def fake_connected(connection)
          if connection.is_a?(SslConnection)
            connection.instance_variable_get(:@io).stub(:connect_nonblock)
          else
            connection.to_io.stub(:connect_nonblock)
          end
        end

        after do
          reactor.stop.value if reactor.running?
        end
      end

      describe '#start' do
        after do
          reactor.stop.value if reactor.running?
        end

        it 'returns a future that is resolved when the reactor has started' do
          reactor.start.value
        end

        it 'returns a future that resolves to the reactor' do
          reactor.start.value.should equal(reactor)
        end

        it 'is running after being started' do
          reactor.start.value
          reactor.should be_running
        end

        it 'calls the selector' do
          called = false
          selector.handler { called = true; [[], [], []] }
          reactor.start.value
          await { called }
          reactor.stop.value
          called.should be_true, 'expected the selector to have been called'
        end

        context 'when stopping' do
          it 'waits for the reactor to stop, then starts it again' do
            barrier = Queue.new
            selector.handler do
              barrier.pop
              [[], [], []]
            end
            reactor.start.value
            stopped_future = reactor.stop
            sequence = []
            stopped_future.on_complete { sequence << :stopped }
            restarted_future = reactor.start
            restarted_future.on_complete { sequence << :restarted }
            barrier.push(nil)
            stopped_future.value
            restarted_future.value
            await { sequence.size >= 2 }
            begin
              sequence.should eq([:stopped, :restarted])
            ensure
              reactor.stop
              barrier.push(nil) while reactor.running?
            end
          end

          it 'restarts the reactor even when restarted before a failed stop' do
            barrier = Queue.new
            selector.handler do
              if barrier.pop == :fail
                raise 'Blurgh'
              else
                [[], [], []]
              end
            end
            reactor.start.value
            stopped_future = reactor.stop
            restarted_future = reactor.start
            crashed = false
            restarted = false
            stopped_future.on_failure { crashed = true }
            restarted_future.on_complete { restarted = true }
            barrier.push(:fail)
            stopped_future.value rescue nil
            restarted_future.value
            await { crashed && restarted }
            begin
              crashed.should be_true
              restarted.should be_true
            ensure
              reactor.stop
              barrier.push(nil) while reactor.running?
            end
          end
        end

        context 'when stopped' do
          before do
            reactor.start.value
            reactor.stop.value
          end

          it 'starts the reactor again' do
            reactor.start.value
            reactor.should be_running
          end
        end

        context 'when already started' do
          it 'is not started again' do
            ticks = Queue.new
            barrier = Queue.new
            selector.handler do
              ticks.push(:tick)
              barrier.pop
              [[], [], []]
            end
            reactor.start.value
            reactor.start.value
            reactor.start.value
            begin
              ticks.pop.should_not be_nil
              ticks.size.should be_zero
            ensure
              reactor.stop
              barrier.push(nil) while reactor.running?
            end
          end
        end
      end

      describe '#stop' do
        include_context 'running_reactor'

        it 'returns a future that is resolved when the reactor has stopped' do
          reactor.start.value
          reactor.stop.value
        end

        it 'returns a future which resolves to the reactor' do
          reactor.start.value
          reactor.stop.value.should equal(reactor)
        end

        it 'is not running after stop completed' do
          reactor.start.value
          reactor.stop.value
          reactor.should_not be_running
        end

        it 'keeps running until stop completes' do
          barrier = Queue.new
          selector.handler do
            barrier.pop
            [[], [], []]
          end
          reactor.start.value
          future = reactor.stop
          barrier.push(nil)
          reactor.should be_running
          barrier.push(nil) until future.completed?
          reactor.should_not be_running
        end

        it 'unblocks the reactor' do
          running_barrier = Queue.new
          selector.handler do |readables, writables, _, _|
            running_barrier.push(nil)
            IO.select(readables, writables, nil, 5)
          end
          reactor.start.value
          running_barrier.pop
          stopped_future = reactor.stop
          await { stopped_future.completed? }
          stopped_future.should be_completed
          stopped_future.value
        end

        it 'drains all sockets' do
          reactor.start.value
          TCPServer.open(0) do |server|
            Thread.start { server.accept }
            connection = reactor.connect(server.addr[3], server.addr[1], 5).value
            writable = false
            connection.stub(:stub_writable?) { writable }
            class <<connection; alias_method :writable?, :stub_writable?; end
            connection.write('12345678')
            release_barrier = barrier = Queue.new
            selector.handler do |readables, writables, _, _|
              barrier.pop
              [[], writables, []]
            end
            await { barrier.num_waiting > 0 }
            barrier = []
            release_barrier.push(nil)
            connection.stub(:flush) do
              writable = false
            end
            writable = true
            reactor.stop.value
            connection.should have_received(:flush)
          end
        end

        it 'waits on drain to complete upto the specified drain timeout' do
          time = time_increment = next_increment = 0
          mutex = Mutex.new
          clock.stub(:now) { mutex.synchronize { time } }
          selector.handler do |_, writables, _, _|
            mutex.synchronize do
              time += time_increment
              time_increment = next_increment
            end
            [[], writables, []]
          end
          reactor.start.value
          TCPServer.open(0) do |server|
            Thread.start { server.accept }
            connection = reactor.connect(server.addr[3], server.addr[1], 5).value
            stopped_future = nil
            mutex.synchronize do
              connection.stub(:writable?).and_return(true)
              connection.stub(:flush)
              next_increment = 1
              stopped_future = reactor.stop
            end
            expect { stopped_future.value }.to raise_error(ReactorError, /timeout/)
            (time).should eq(3)
          end
        end

        it 'waits on drain to complete upto five seconds by default' do
          with_server do |host, port|
            options.delete(:drain_timeout)
            time = time_increment = next_increment = 0
            mutex = Mutex.new
            clock.stub(:now) { mutex.synchronize { time } }
            selector.handler do |_, writables, _, _|
              mutex.synchronize do
                time += time_increment
                time_increment = next_increment
              end
              [[], writables, []]
            end
            reactor.start.value
            connection = reactor.connect(host, port, 5).value
            stopped_future = nil
            mutex.synchronize do
              connection.stub(:writable?).and_return(true)
              connection.stub(:flush)
              next_increment = 1
              stopped_future = reactor.stop
            end
            expect { stopped_future.value }.to raise_error(ReactorError, /timeout/)
            time.should eq(5)
          end
        end

        it 'closes all sockets' do
          with_server do |host, port|
            reactor.start.value
            connection = reactor.connect(host, port, 5).value
            reactor.stop.value
            connection.should be_closed
          end
        end

        it 'closes all sockets even if drain fails' do
          with_server do |host, port|
            reactor.start.value
            connection = reactor.connect(host, port, 5).value
            Thread.pass
            writable = false
            connection.stub(:stub_writable?) { writable }
            class <<connection; alias_method :writable?, :stub_writable?; end
            connection.write('12345678')
            Thread.pass
            connection.stub(:flush).and_raise(StandardError, 'Boork')
            writable = true
            f = reactor.stop
            expect { f.value }.to raise_error(StandardError, 'Boork')
            connection.should be_closed
          end
        end

        it 'cancels all active timers' do
          reactor.start.value
          clock.stub(:now).and_return(1)
          expired_timer = reactor.schedule_timer(1)
          active_timer1 = reactor.schedule_timer(999)
          active_timer2 = reactor.schedule_timer(111)
          expired_timer.should_not_receive(:fail)
          clock.stub(:now).and_return(2)
          await { expired_timer.completed? }
          reactor.stop.value
          active_timer1.should be_failed
          active_timer2.should be_failed
        end

        context 'when not started' do
          it 'does nothing' do
            reactor = described_class.new(selector: selector, clock: clock)
            expect { reactor.stop.value }.to_not raise_error
          end
        end

        context 'when already stopped' do
          it 'does nothing' do
            reactor.stop.value
            expect { reactor.stop.value }.to_not raise_error
          end
        end
      end

      describe '#on_error' do
        before do
          selector.handler { raise 'Blurgh' }
        end

        it 'calls the listeners when the reactor crashes' do
          error = nil
          reactor.on_error { |e| error = e }
          reactor.start
          await { error }
          error.message.should eq('Blurgh')
        end

        it 'calls the listener immediately when the reactor has already crashed' do
          error = nil
          reactor.start.value
          await { !reactor.running? }
          reactor.on_error { |e| error = e }
          await { error }
        end

        it 'ignores errors raised by listeners' do
          called = false
          reactor.on_error { raise 'Blurgh' }
          reactor.on_error { called = true }
          reactor.start
          await { called }
          called.should be_true, 'expected all close listeners to have been called'
        end

        it 'calls all listeners when the reactor crashes after being restarted' do
          calls = []
          barrier = Queue.new
          selector.handler { barrier.pop; raise 'Blurgh' }
          reactor.on_error { calls << :pre_started }
          reactor.start
          reactor.on_error { calls << :post_started }
          barrier.push(nil)
          await { !reactor.running? }
          await { calls.size >= 2 }
          reactor.on_error { calls << :pre_restarted }
          calls.should eq([
            :pre_started,
            :post_started,
            :pre_restarted,
          ])
          reactor.start
          reactor.on_error { calls << :post_restarted }
          barrier.push(nil)
          await { !reactor.running? }
          calls.should eq([
            :pre_started,
            :post_started,
            :pre_restarted,
            :pre_started,
            :post_started,
            :pre_restarted,
            :post_restarted,
          ])
        end
      end

      describe '#connect' do
        include_context 'running_reactor'

        it 'calls the given block with a connection' do
          with_server do |host, port|
            connection = nil
            reactor.start.value
            reactor.connect(host, port, 5) { |c| connection = c }.value
            connection.should_not be_nil
          end
        end

        it 'returns a future that resolves to what the given block returns' do
          with_server do |host, port|
            reactor.start.value
            x = reactor.connect(host, port, 5) { :foo }.value
            x.should eq(:foo)
          end
        end

        it 'defaults to 5 as the connection timeout' do
          with_server do |host, port|
            reactor.start.value
            connection = reactor.connect(host, port).value
            connection.connection_timeout.should eq(5)
          end
        end

        it 'takes the connection timeout from the :timeout option' do
          with_server do |host, port|
            reactor.start.value
            connection = reactor.connect(host, port, timeout: 9).value
            connection.connection_timeout.should eq(9)
          end
        end

        it 'returns the connection when no block is given' do
          with_server do |host, port|
            reactor.start.value
            reactor.connect(host, port, 5).value.should be_a(Connection)
          end
        end

        it 'creates a connection and passes it to the selector as a readable' do
          with_server do |host, port|
            reactor.start.value
            connection = reactor.connect(host, port, 5).value
            await { selector.last_arguments[0].length > 1 }
            selector.last_arguments[0].should include(connection)
          end
        end

        it 'upgrades the connection to SSL' do
          with_server do |host, port|
            reactor.start.value
            connection = reactor.connect(host, port, ssl: true).value
            connection.should be_a(SslConnection)
          end
        end

        it 'passes an SSL context to the SSL connection' do
          with_server do |host, port|
            ssl_context = double(:ssl_context)
            reactor.start.value
            f = reactor.connect(host, port, ssl: ssl_context)
            expect { f.value }.to raise_error
          end
        end

        context 'when called before the reactor is started' do
          it 'waits for the reactor to start' do
            with_server do |host, port|
              f = reactor.connect(host, port)
              reactor.start.value
              f.value
            end
          end
        end

        context 'when called after the reactor has stopped' do
          it 'waits for the reactor to be restarted' do
            with_server do |host, port|
              reactor.start.value
              reactor.stop.value
              f = reactor.connect(host, port)
              reactor.start.value
              f.value
            end
          end
        end
      end

      describe '#bind' do
        include_context 'running_reactor'

        let :port do
          2**15 + rand(2**15)
        end

        it 'calls the given block with an acceptor' do
          acceptor = nil
          reactor.start.value
          reactor.bind(ENV['SERVER_HOST'], port, 5) { |a| acceptor = a }.value
          acceptor.should_not be_nil
        end

        it 'returns a future that resolves to what the given block returns' do
          reactor.start.value
          x = reactor.bind(ENV['SERVER_HOST'], port, 5) { |acceptor| :foo }.value
          x.should eq(:foo)
        end

        it 'defaults to a backlog of 5' do
          reactor.start.value
          acceptor = reactor.bind(ENV['SERVER_HOST'], port).value
          acceptor.backlog.should eq(5)
        end

        it 'takes the backlog from the :backlog option' do
          reactor.start.value
          acceptor = reactor.bind(ENV['SERVER_HOST'], port, backlog: 9).value
          acceptor.backlog.should eq(9)
        end

        it 'returns the acceptor when no block is given' do
          reactor.start.value
          acceptor = reactor.bind(ENV['SERVER_HOST'], port, 5).value
          acceptor.should be_an(Acceptor)
        end

        it 'creates an acceptor and passes it to the selector as a readable' do
          reactor.start.value
          acceptor = reactor.bind(ENV['SERVER_HOST'], port, 5).value
          await { selector.last_arguments && selector.last_arguments[0].length > 1 }
          selector.last_arguments[0].should include(acceptor)
        end

        it 'creates an SSL acceptor' do
          ssl_context = double(:ssl_context)
          reactor.start.value
          acceptor = reactor.bind(ENV['SERVER_HOST'], port, ssl: ssl_context).value
          acceptor.should be_an(SslAcceptor)
        end

        context 'when called before the reactor is started' do
          it 'waits for the reactor to start' do
            f = reactor.bind(ENV['SERVER_HOST'], port, 5)
            reactor.start.value
            f.value
          end
        end

        context 'when called after the reactor has stopped' do
          it 'waits for the reactor to be restarted' do
            reactor.start.value
            reactor.stop.value
            f = reactor.bind(ENV['SERVER_HOST'], port, 5)
            reactor.start.value
            f.value
          end
        end
      end

      describe '#schedule_timer' do
        context 'when the reactor is running' do
          before do
            reactor.start.value
          end

          after do
            reactor.stop.value
          end

          it 'returns a future that is resolved after the specified duration' do
            start = Time.now
            clock.stub(:now).and_return(1)
            f = reactor.schedule_timer(8)
            clock.stub(:now).and_return(10.1)
            await { f.resolved? }
            expect(Time.now - start).to be < 1
          end
        end

        context 'when called before the reactor is started' do
          after do
            reactor.stop.value if reactor.running?
          end

          it 'waits for the reactor to start' do
            clock.stub(:now).and_return(1)
            f = reactor.schedule_timer(0.1)
            clock.stub(:now).and_return(2)
            reactor.start.value
            f.value
          end
        end

        context 'when called after the reactor has stopped' do
          after do
            reactor.stop.value if reactor.running?
          end

          it 'waits for the reactor to be restarted' do
            reactor.start.value
            reactor.stop.value
            clock.stub(:now).and_return(1)
            f = reactor.schedule_timer(0.1)
            clock.stub(:now).and_return(2)
            reactor.start.value
            f.value
          end
        end
      end

      describe '#cancel_timer' do
        before do
          reactor.start.value
        end

        after do
          reactor.stop.value
        end

        it 'fails the timer future' do
          clock.stub(:now).and_return(1)
          f = reactor.schedule_timer(0.1)
          reactor.cancel_timer(f)
          await { f.failed? }
        end

        it 'does not trigger the timer future when it expires' do
          clock.stub(:now).and_return(1)
          f = reactor.schedule_timer(0.1)
          reactor.cancel_timer(f)
          clock.stub(:now).and_return(1.1)
          await { f.failed? }
        end

        it 'fails the future with a CancelledError' do
          clock.stub(:now).and_return(1)
          f = reactor.schedule_timer(0.1)
          reactor.cancel_timer(f)
          await { f.failed? }
          expect { f.value }.to raise_error(CancelledError)
        end

        it 'does nothing when the timer has already expired' do
          clock.stub(:now).and_return(1)
          f = reactor.schedule_timer(0.1)
          clock.stub(:now).and_return(1.1)
          await { f.resolved? }
          reactor.cancel_timer(f)
        end

        it 'does nothing when given a future that is not a timer' do
          reactor.cancel_timer(Ione::Promise.new.future)
        end

        it 'does nothing when given something that is not a future' do
          reactor.cancel_timer(:foobar)
        end

        it 'does nothing when given nil' do
          reactor.cancel_timer(nil)
        end

        context 'when called before the reactor is started' do
          it 'removes the timer before the reactor starts' do
            clock.stub(:now).and_return(1)
            f = reactor.schedule_timer(0.1)
            reactor.cancel_timer(f)
            clock.stub(:now).and_return(2)
            f.should be_failed
            reactor.start.value
          end
        end

        context 'when called after the reactor has stopped' do
          it 'removes the timer before the reactor is started again' do
            reactor.start.value
            reactor.stop.value
            clock.stub(:now).and_return(1)
            f = reactor.schedule_timer(0.1)
            reactor.cancel_timer(f)
            f.should be_failed
            reactor.start.value
          end
        end
      end

      describe '#to_s' do
        context 'returns a string that' do
          it 'includes the class name' do
            reactor.to_s.should include('Ione::Io::IoReactor')
          end

          it 'includes the state' do
            reactor.to_s.should include('PENDING')
          end
        end
      end
    end

    describe IoLoopBody do
      let :loop_body do
        described_class.new(unblocker, selector: selector, clock: clock)
      end

      let :unblocker do
        double(:unblocker, connected?: true, connecting?: false, writable?: false, closed?: false)
      end

      let :selector do
        double(:selector)
      end

      let :clock do
        double(:clock, now: 0)
      end

      let :socket do
        double(:socket, connected?: false, connecting?: false, writable?: false, closed?: false)
      end

      before do
        unblocker.stub(:close) { unblocker.stub(:closed?).and_return(true) }
      end

      describe '#tick' do
        before do
          loop_body.add_socket(socket)
        end

        it 'passes the unblocker to the selector as the first readable' do
          socket.stub(:connected?).and_return(true)
          selector.should_receive(:select).with([unblocker, socket], anything, anything, anything).and_return([nil, nil, nil])
          loop_body.tick
        end

        it 'passes connected sockets as readables to the selector' do
          socket.stub(:connected?).and_return(true)
          selector.should_receive(:select).with([unblocker, socket], anything, anything, anything).and_return([nil, nil, nil])
          loop_body.tick
        end

        it 'passes writable sockets as writable to the selector' do
          socket.stub(:writable?).and_return(true)
          selector.should_receive(:select).with(anything, [socket], anything, anything).and_return([nil, nil, nil])
          loop_body.tick
        end

        it 'passes writable sockets as both readable and writable to the selector' do
          socket.stub(:connected?).and_return(true)
          socket.stub(:writable?).and_return(true)
          selector.should_receive(:select).with([unblocker, socket], [socket], anything, anything).and_return([nil, nil, nil])
          loop_body.tick
        end

        it 'passes connecting sockets as writable to the selector' do
          socket.stub(:connecting?).and_return(true)
          socket.stub(:connect)
          selector.should_receive(:select).with(anything, [socket], anything, anything).and_return([nil, nil, nil])
          loop_body.tick
        end

        it 'filters out closed sockets' do
          socket.stub(:closed?).and_return(true)
          selector.should_receive(:select).with([unblocker], [], anything, anything).and_return([nil, nil, nil])
          loop_body.tick
        end

        it 'does nothing when IO.select raises Errno::EBADF' do
          selector.should_receive(:select) do
            raise Errno::EBADF
          end
          loop_body.tick
        end

        it 'does nothing when IO.select raises IOError' do
          selector.should_receive(:select) do
            raise IOError
          end
          loop_body.tick
        end

        it 'calls #read on all readable sockets returned by the selector' do
          socket.stub(:connected?).and_return(true)
          socket.should_receive(:read)
          selector.stub(:select) do |r, w, _, _|
            [[socket], nil, nil]
          end
          loop_body.tick
        end

        it 'calls #connect on all connecting sockets' do
          socket.stub(:connecting?).and_return(true)
          socket.should_receive(:connect)
          selector.stub(:select).and_return([nil, nil, nil])
          loop_body.tick
        end

        it 'calls #flush on all writable sockets returned by the selector' do
          socket.stub(:writable?).and_return(true)
          socket.should_receive(:flush)
          selector.stub(:select) do |r, w, _, _|
            [nil, [socket], nil]
          end
          loop_body.tick
        end

        it 'allows the caller to specify a custom timeout' do
          loop_body = described_class.new(unblocker, selector: selector, clock: clock, tick_resolution: 99)
          selector.should_receive(:select).with(anything, anything, anything, 99).and_return([[], [], []])
          loop_body.tick
        end
      end

      describe '#close_sockets' do
        it 'closes all sockets' do
          socket1 = double(:socket1, closed?: false)
          socket2 = double(:socket2, closed?: false)
          socket1.should_receive(:close)
          socket2.should_receive(:close)
          loop_body.add_socket(socket1)
          loop_body.add_socket(socket2)
          loop_body.close_sockets
        end

        it 'closes all sockets, even when one of them raises an error' do
          socket1 = double(:socket1, closed?: false)
          socket2 = double(:socket2, closed?: false)
          socket1.stub(:close).and_raise('Blurgh')
          socket2.should_receive(:close)
          loop_body.add_socket(socket1)
          loop_body.add_socket(socket2)
          loop_body.close_sockets
        end
      end
    end

    describe Scheduler do
      let :scheduler do
        described_class.new(clock: clock)
      end

      let :clock do
        double(:clock, now: 0)
      end

      describe '#tick' do
        it 'completes timers that have expired' do
          clock.stub(:now).and_return(1)
          future = scheduler.schedule_timer(1)
          scheduler.tick
          future.should_not be_completed
          clock.stub(:now).and_return(2)
          scheduler.tick
          future.should be_completed
        end

        it 'clears out timers that have expired' do
          clock.stub(:now).and_return(1)
          future = scheduler.schedule_timer(1)
          clock.stub(:now).and_return(2)
          scheduler.tick
          future.should be_completed
          expect { scheduler.tick }.to_not raise_error
        end
      end

      describe '#cancel_timers' do
        it 'fails all active timers with a CancelledError' do
          clock.stub(:now).and_return(1)
          f1 = scheduler.schedule_timer(1)
          f2 = scheduler.schedule_timer(3)
          f3 = scheduler.schedule_timer(3)
          clock.stub(:now).and_return(2)
          scheduler.tick
          scheduler.cancel_timers
          f1.should be_completed
          f2.should be_failed
          f3.should be_failed
          expect { f3.value }.to raise_error(CancelledError)
        end
      end
    end
  end
end

module IoReactorSpec
  class FakeSelector
    attr_reader :last_arguments

    def initialize
      handler { [[], [], []] }
    end

    def handler(&body)
      @body = body
    end

    def select(*args)
      @last_arguments = args
      @body.call(*args)
    end
  end
end
