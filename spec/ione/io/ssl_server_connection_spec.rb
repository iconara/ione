# encoding: utf-8

require 'spec_helper'
require 'ione/io/connection_common'


module Ione
  module Io
    describe SslServerConnection do
      let :handler do
        described_class.new(socket, 'example.com', 4444, unblocker, ssl_context, accept_callback, ssl_socket_impl)
      end

      let :socket do
        double(:socket, close: nil)
      end

      let :unblocker do
        double(:unblocker)
      end

      let :ssl_context do
        double(:ssl_context)
      end

      let :ssl_socket do
        double(:ssl_socket)
      end

      let :ssl_socket_impl do
        double(:ssl_socket_impl)
      end

      let :accept_callback do
        double(:accept_callback, call: nil)
      end

      before do
        ssl_socket_impl.stub(:new).with(socket, ssl_context).and_return(ssl_socket)
        ssl_socket.stub(:to_io).and_return(socket)
      end

      describe '#to_io' do
        it 'returns the raw socket' do
          handler.to_io.should equal(socket)
        end

        it 'returns an SSL socket once the SSL connection has been established' do
          ssl_socket.stub(:accept_nonblock)
          handler.read
          handler.to_io.should equal(socket)
        end
      end

      describe '#read' do
        it 'creates an SSL socket with the specified SSL context' do
          ssl_socket.stub(:accept_nonblock)
          handler.read
          ssl_socket_impl.should have_received(:new).with(socket, ssl_context)
        end

        it 'accepts the SSL connection' do
          ssl_socket.stub(:accept_nonblock)
          handler.read
          ssl_socket.should have_received(:accept_nonblock)
        end

        it 'calls the callback once the SSL connection has been established' do
          ssl_socket.stub(:accept_nonblock)
          handler.read
          accept_callback.should have_received(:call).with(handler)
        end

        it 'reads properly once the SSL connection has been established' do
          ssl_socket.stub(:accept_nonblock)
          ssl_socket.stub(:read_nonblock)
          handler.read
          handler.read
          ssl_socket.should have_received(:read_nonblock)
        end

        it 'continues to attempt to accept the SSL connection until it succeeds' do
          ssl_socket.stub(:accept_nonblock).and_raise(OpenSSL::SSL::SSLError, 'would block')
          ssl_socket.stub(:read_nonblock)
          handler.read
          handler.read
          handler.read
          ssl_socket.stub(:accept_nonblock)
          handler.read
          handler.read
          ssl_socket.should have_received(:read_nonblock)
        end

        it 'closes the connection when the SSL accept fails with an SSLError' do
          ssl_socket.stub(:accept_nonblock).and_raise(OpenSSL::SSL::SSLError, 'general bork')
          handler.read
          handler.should be_closed
        end

        it 'closes the connection when the SSL accept fails for another reason' do
          ssl_socket.stub(:accept_nonblock).and_raise(StandardError, 'general bork')
          handler.read
          handler.should be_closed
        end
      end
    end
  end
end
