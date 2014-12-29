# encoding: utf-8

require 'spec_helper'
require 'ione/io/connection_common'


module Ione
  module Io
    describe Connection do
      let :handler do
        described_class.new('example.com', 55555, 5, unblocker, clock, socket_impl)
      end

      let :unblocker do
        double(:unblocker, unblock: nil)
      end

      let :socket_impl do
        double(:socket_impl)
      end

      let :clock do
        double(:clock, now: 0)
      end

      let :socket do
        double(:socket)
      end

      before do
        socket_impl.stub(:getaddrinfo)
          .with('example.com', 55555, nil, Socket::SOCK_STREAM)
          .and_return([[nil, 'PORT', nil, 'IP1', 'FAMILY1', 'TYPE1'], [nil, 'PORT', nil, 'IP2', 'FAMILY2', 'TYPE2']])
        socket_impl.stub(:sockaddr_in)
          .with('PORT', 'IP1')
          .and_return('SOCKADDR1')
        socket_impl.stub(:new)
          .with('FAMILY1', 'TYPE1', 0)
          .and_return(socket)
      end

      before do
        socket.stub(:connect_nonblock)
        socket.stub(:close)
      end

      it_behaves_like 'a connection' do
        before do
          handler.connect
        end
      end

      describe '#connect' do
        it 'creates a socket and calls #connect_nonblock' do
          handler.connect
          socket.should have_received(:connect_nonblock).with('SOCKADDR1')
        end

        it 'handles EINPROGRESS that #connect_nonblock raises' do
          socket.stub(:connect_nonblock).and_raise(Errno::EINPROGRESS)
          handler.connect
        end

        it 'is connecting after #connect has been called' do
          socket.stub(:connect_nonblock).and_raise(Errno::EINPROGRESS)
          handler.connect
          handler.should be_connecting
        end

        it 'is connecting even after the second call' do
          socket.stub(:connect_nonblock).and_raise(Errno::EINPROGRESS)
          handler.connect
          handler.connect
          handler.should be_connecting
          socket.should have_received(:connect_nonblock).twice
        end

        it 'does not create a new socket the second time' do
          socket_impl.stub(:new).and_return(socket)
          socket.stub(:connect_nonblock).and_raise(Errno::EINPROGRESS)
          handler.connect
          handler.connect
          socket_impl.should have_received(:new).once
        end

        it 'attempts another connect the second time' do
          socket.stub(:connect_nonblock).and_raise(Errno::EINPROGRESS)
          handler.connect
          handler.connect
          socket.should have_received(:connect_nonblock).twice
        end

        shared_examples 'on successfull connection' do
          it 'fulfilles the returned future and returns itself' do
            f = handler.connect
            f.should be_resolved
            f.value.should equal(handler)
          end

          it 'is connected' do
            handler.connect
            handler.should be_connected
          end

          it 'calls the connected listeners' do
            called = false
            handler.on_connected { called = true }
            handler.connect
            called.should be_true
          end
        end

        context 'when #connect_nonblock does not raise any error' do
          before do
            socket.stub(:connect_nonblock)
          end

          include_examples 'on successfull connection'
        end

        context 'when #connect_nonblock raises EISCONN' do
          before do
            socket.stub(:connect_nonblock).and_raise(Errno::EISCONN)
          end

          include_examples 'on successfull connection'
        end

        context 'when #connect_nonblock raises EALREADY' do
          it 'it does nothing' do
            socket.stub(:connect_nonblock).and_raise(Errno::EALREADY)
            f = handler.connect
            f.should_not be_resolved
            f.should_not be_failed
          end
        end

        context 'when #connect_nonblock raises EINVAL' do
          before do
            socket_impl.stub(:sockaddr_in)
              .with('PORT', 'IP2')
              .and_return('SOCKADDR2')
            socket_impl.stub(:new)
              .with('FAMILY2', 'TYPE2', 0)
              .and_return(socket)
            socket.stub(:close)
          end

          it 'attempts to connect to the next address given by #getaddinfo' do
            socket.should_receive(:connect_nonblock).with('SOCKADDR1').and_raise(Errno::EINVAL)
            socket.should_receive(:connect_nonblock).with('SOCKADDR2')
            handler.connect
          end

          it 'fails if there are no more addresses to try' do
            socket.stub(:connect_nonblock).and_raise(Errno::EINVAL)
            f = handler.connect
            expect { f.value }.to raise_error(ConnectionError)
          end
        end

        context 'when #connect_nonblock raises ECONNREFUSED' do
          before do
            socket_impl.stub(:sockaddr_in)
              .with('PORT', 'IP2')
              .and_return('SOCKADDR2')
            socket_impl.stub(:new)
              .with('FAMILY2', 'TYPE2', 0)
              .and_return(socket)
            socket.stub(:close)
          end

          it 'attempts to connect to the next address given by #getaddinfo' do
            socket.should_receive(:connect_nonblock).with('SOCKADDR1').and_raise(Errno::ECONNREFUSED)
            socket.should_receive(:connect_nonblock).with('SOCKADDR2')
            handler.connect
          end

          it 'fails if there are no more addresses to try' do
            socket.stub(:connect_nonblock).and_raise(Errno::ECONNREFUSED)
            f = handler.connect
            expect { f.value }.to raise_error(ConnectionError)
          end
        end

        context 'when #connect_nonblock raises SystemCallError' do
          before do
            socket.stub(:connect_nonblock).and_raise(SystemCallError.new('Bork!', 9999))
            socket.stub(:close)
          end

          it 'fails the future with a ConnectionError' do
            f = handler.connect
            expect { f.value }.to raise_error(ConnectionError)
          end

          it 'closes the socket' do
            socket.should_receive(:close)
            handler.connect
          end

          it 'calls the closed listener' do
            called = false
            handler.on_closed { called = true }
            handler.connect
            called.should be_true, 'expected the close listener to have been called'
          end

          it 'passes the error to the close listener' do
            error = nil
            handler.on_closed { |e| error = e }
            handler.connect
            error.should be_a(Exception)
          end

          it 'is closed' do
            handler.connect
            handler.should be_closed
          end
        end

        context 'when Socket.getaddrinfo raises SocketError' do
          before do
            socket_impl.stub(:getaddrinfo).and_raise(SocketError)
          end

          it 'fails the returned future with a ConnectionError' do
            f = handler.connect
            expect { f.value }.to raise_error(ConnectionError)
          end

          it 'calls the close listener' do
            called = false
            handler.on_closed { called = true }
            handler.connect
            called.should be_true, 'expected the close listener to have been called'
          end

          it 'passes the error to the close listener' do
            error = nil
            handler.on_closed { |e| error = e }
            handler.connect
            error.should be_a(Exception)
          end

          it 'is closed' do
            handler.connect
            handler.should be_closed
          end
        end

        context 'when it takes longer than the connection timeout to connect' do
          before do
            socket.stub(:connect_nonblock).and_raise(Errno::EINPROGRESS)
            socket.stub(:close)
          end

          it 'fails the returned future with a ConnectionTimeoutError' do
            f = handler.connect
            clock.stub(:now).and_return(1)
            handler.connect
            socket.should_receive(:close)
            clock.stub(:now).and_return(7)
            handler.connect
            f.should be_failed
            expect { f.value }.to raise_error(ConnectionTimeoutError)
          end

          it 'closes the connection' do
            handler.connect
            clock.stub(:now).and_return(1)
            handler.connect
            socket.should_receive(:close)
            clock.stub(:now).and_return(7)
            handler.connect
          end

          it 'delivers a ConnectionTimeoutError to the close handler' do
            error = nil
            handler.on_closed { |e| error = e }
            handler.connect
            clock.stub(:now).and_return(7)
            handler.connect
            error.should be_a(ConnectionTimeoutError)
          end
        end
      end

      describe '#to_io' do
        before do
          socket.stub(:connect_nonblock)
          socket.stub(:close)
        end

        it 'returns nil initially' do
          handler.to_io.should be_nil
        end

        it 'returns the socket when connected' do
          handler.connect
          handler.to_io.should equal(socket)
        end

        it 'returns nil when closed' do
          handler.connect
          handler.close
          handler.to_io.should be_nil
        end
      end

      describe '#to_s' do
        context 'returns a string that' do
          it 'includes the class name' do
            handler.to_s.should include(described_class.name.to_s)
          end

          it 'includes the host and port' do
            handler.to_s.should include('example.com:55555')
          end

          it 'includes the connection state' do
            handler.to_s.should include('CONNECTING')
            socket.stub(:connect_nonblock).and_raise(Errno::EINPROGRESS)
            handler.connect
            handler.to_s.should include('CONNECTING')
            socket.stub(:connect_nonblock)
            handler.connect
            handler.to_s.should include('CONNECTED')
            handler.close
            handler.to_s.should include('CLOSED')
          end
        end
      end
    end
  end
end
