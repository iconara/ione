# encoding: utf-8

require 'spec_helper'


describe 'An IO reactor' do
  let :io_reactor do
    Ione::Io::IoReactor.new
  end

  context 'schedules timers' do
    let :io_reactor do
      Ione::Io::IoReactor.new(tick_resolution: 3)
    end

    it 'resolves timers on time even when they expire before the reactor is scheduled to wake up next' do
      io_reactor.start.value
      start_time = Time.now
      timer_future = io_reactor.schedule_timer(0.3)
      io_reactor.schedule_timer(0.1).value
      (Time.now - start_time).should <= 0.2
      timer_future.value
      (Time.now - start_time).should <= 0.4
    end
  end

  context 'connecting to a generic server' do
    let :protocol_handler_factory do
      lambda { |c| IoSpec::TestConnection.new(c) }
    end

    let :fake_server do
      FakeServer.new
    end

    before do
      fake_server.start
      io_reactor.start
    end

    after do
      io_reactor.stop
      fake_server.stop
    end

    it 'connects to the server' do
      io_reactor.connect(ENV['SERVER_HOST'], fake_server.port, 1, &protocol_handler_factory)
      fake_server.await_connects(1)
    end

    it 'receives data' do
      protocol_handler = io_reactor.connect(ENV['SERVER_HOST'], fake_server.port, 1, &protocol_handler_factory).value
      fake_server.await_connects(1)
      fake_server.broadcast('hello world')
      await { protocol_handler.data.bytesize > 0 }
      protocol_handler.data.should == 'hello world'
    end

    it 'receives data on multiple connections' do
      protocol_handlers = Array.new(10) { io_reactor.connect(ENV['SERVER_HOST'], fake_server.port, 1, &protocol_handler_factory).value }
      fake_server.await_connects(10)
      fake_server.broadcast('hello world')
      await { protocol_handlers.all? { |c| c.data.bytesize > 0 } }
      protocol_handlers.sample.data.should == 'hello world'
    end
  end

  context 'running an echo server' do
    let :protocol_handler_factory do
      lambda do |acceptor|
        acceptor.on_accept do |connection|
          connection.on_data do |data|
            connection.write(data)
          end
        end
      end
    end

    let :port do
      2**15 + rand(2**15)
    end

    before do
      io_reactor.start.value
    end

    after do
      io_reactor.stop.value
    end

    it 'starts a server' do
      io_reactor.bind(ENV['SERVER_HOST'], port, 1, &protocol_handler_factory).value
    end

    it 'starts a server that listens to the specified port' do
      io_reactor.bind(ENV['SERVER_HOST'], port, 1, &protocol_handler_factory).value
      socket = TCPSocket.new(ENV['SERVER_HOST'], port)
      socket.puts('HELLO')
      result = socket.read(5)
      result.should == 'HELLO'
      socket.close
    end
  end
end

module IoSpec
  class TestConnection
    def initialize(connection)
      @connection = connection
      @connection.on_data(&method(:receive_data))
      @lock = Mutex.new
      @data = Ione::ByteBuffer.new
    end

    def data
      @lock.synchronize { @data.to_s }
    end

    private

    def receive_data(new_data)
      @lock.synchronize { @data << new_data }
    end
  end
end