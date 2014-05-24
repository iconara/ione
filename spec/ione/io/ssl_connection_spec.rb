# encoding: utf-8

require 'spec_helper'
require 'ione/io/connection_common'


module Ione
  module Io
    describe SslConnection do
      let :handler do
        described_class.new('example.com', 55555, raw_socket, unblocker, ssl_context, socket_impl)
      end

      let :socket_impl do
        double(:socket_impl)
      end

      let :raw_socket do
        double(:raw_socket)
      end

      let :ssl_socket do
        double(:ssl_socket)
      end

      let :unblocker do
        double(:unblocker, unblock!: nil)
      end

      let :ssl_context do
        double(:ssl_context)
      end

      before do
        socket_impl.stub(:new).with(raw_socket, ssl_context).and_return(ssl_socket)
      end

      before do
        ssl_socket.stub(:connect_nonblock)
        ssl_socket.stub(:close)
      end

      it_behaves_like 'a connection', skip_read: true do
        let :socket do
          ssl_socket
        end

        before do
          handler.connect
        end
      end

      describe '#connect' do
        it 'creates an SSL socket and passes in the specified SSL context' do
          handler.connect
          socket_impl.should have_received(:new).with(raw_socket, ssl_context)
        end

        it 'does not pass the context parameter when the SSL context is nil' do
          socket_impl.stub(:new).and_return(ssl_socket)
          h = described_class.new('example.com', 55555, raw_socket, unblocker, nil, socket_impl)
          h.connect
          socket_impl.should have_received(:new).with(raw_socket)
        end

        it 'calls #connect_nonblock on the SSL socket' do
          handler.connect
          ssl_socket.should have_received(:connect_nonblock)
        end

        it 'does nothing when the socket raises a "would block" error' do
          ssl_socket.stub(:connect_nonblock).and_raise(OpenSSL::SSL::SSLError.new('would block'))
          expect { handler.connect }.to_not raise_error
        end

        it 'returns a future that resolves when the socket is connected' do
          ssl_socket.stub(:connect_nonblock).and_raise(OpenSSL::SSL::SSLError.new('would block'))
          f = handler.connect
          f.should_not be_resolved
          ssl_socket.stub(:connect_nonblock).and_return(nil)
          handler.connect
          f.should be_resolved
        end

        it 'is connected when #connect_nonblock does not raise' do
          handler.connect
          handler.should be_connected
        end

        it 'fails when #connect_nonblock raises an error that does not include the words "would block"' do
          ssl_socket.stub(:connect_nonblock).and_raise(OpenSSL::SSL::SSLError.new('general bork'))
          expect { handler.connect.value }.to raise_error(Ione::Io::ConnectionError)
        end

        it 'is closed when #connect_nonblock raises something that is not a "would block" error' do
          ssl_socket.stub(:connect_nonblock).and_raise(OpenSSL::SSL::SSLError.new('general bork'))
          handler.connect
          handler.should be_closed
        end
      end

      describe '#to_io' do
        it 'returns the raw socket' do
          handler.to_io.should equal(raw_socket)
        end
      end

      describe '#read' do
        if RUBY_ENGINE == 'jruby'
          it 'reads chunks until #read_nonblock raises OpenSSL::SSL::SSLErrorWaitReadable' do
            read_sizes = []
            counter = 3
            ssl_socket.stub(:read_nonblock) do |read_size|
              read_sizes << read_size
              if counter == 0
                raise OpenSSL::SSL::SSLErrorWaitReadable, 'read would block'
              end
              counter -= 1
              'bar'
            end
            handler.connect
            handler.read
            read_sizes.drop(1).should == [read_sizes.first] * 3
          end
        else
          it 'reads and initial chunk of data' do
            data = []
            handler.on_data { |d| data << d }
            ssl_socket.stub(:pending).and_return(0)
            ssl_socket.stub(:read_nonblock).and_return('fooo')
            handler.connect
            handler.read
            data.should == ['fooo']
          end

          it 'reads once, and then again with the value of #pending, until #pending returns zero' do
            read_sizes = []
            counter = 3
            ssl_socket.stub(:pending).and_return(0)
            ssl_socket.stub(:read_nonblock) do |read_size|
              read_sizes << read_size
              ssl_socket.stub(:pending).and_return(counter)
              counter -= 1
              'bar'
            end
            handler.connect
            handler.read
            read_sizes.drop(1).should == [3, 2, 1]
          end
        end
      end
    end
  end
end
