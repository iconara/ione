# encoding: utf-8

require 'spec_helper'


describe 'An IO reactor' do
  let :io_reactor do
    Ione::Io::IoReactor.new
  end

  context 'with a generic server' do
    let :protocol_handler_factory do
      lambda { |c| IoSpec::TestConnection.new(c) }
    end

    let :fake_server do
      FakeServer.new
    end

    before do
      fake_server.start!
      io_reactor.start
    end

    after do
      io_reactor.stop
      fake_server.stop!
    end

    it 'connects to the server' do
      io_reactor.connect(ENV['SERVER_HOST'], fake_server.port, 1).map(&protocol_handler_factory)
      fake_server.await_connects!(1)
    end

    it 'receives data' do
      protocol_handler = io_reactor.connect(ENV['SERVER_HOST'], fake_server.port, 1).map(&protocol_handler_factory).value
      fake_server.await_connects!(1)
      fake_server.broadcast!('hello world')
      await { protocol_handler.data.bytesize > 0 }
      protocol_handler.data.should == 'hello world'
    end

    it 'receives data on multiple connections' do
      protocol_handlers = Array.new(10) { io_reactor.connect(ENV['SERVER_HOST'], fake_server.port, 1).map(&protocol_handler_factory).value }
      fake_server.await_connects!(10)
      fake_server.broadcast!('hello world')
      await { protocol_handlers.all? { |c| c.data.bytesize > 0 } }
      protocol_handlers.sample.data.should == 'hello world'
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