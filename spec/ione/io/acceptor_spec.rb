# encoding: utf-8

require 'spec_helper'


module Ione
  module Io
    describe Acceptor do
      let :acceptor do
        described_class.new('example.com', 4321, backlog, unblocker, reactor, socket_impl)
      end

      let :backlog do
        3
      end

      let :unblocker do
        double(:unblocker)
      end

      let :reactor do
        double(:reactor)
      end

      let :socket_impl do
        double(:socket_impl)
      end

      let :socket do
        double(:socket)
      end

      shared_context 'accepting_connections' do
        let :client_socket do
          double(:client_socket)
        end

        let :accepted_handlers do
          []
        end

        before do
          socket_impl.stub(:unpack_sockaddr_in).with('SOCKADDRX').and_return([3333, 'example.com'])
          socket.stub(:bind)
          socket.stub(:accept_nonblock).and_return([client_socket, 'SOCKADDRX'])
          reactor.stub(:accept) { |h| accepted_handlers << h }
        end
      end

      before do
        socket_impl.stub(:getaddrinfo)
          .with('example.com', 4321, nil, Socket::SOCK_STREAM)
          .and_return([[nil, 'PORT', nil, 'IP1', 'FAMILY1', 'TYPE1'], [nil, 'PORT', nil, 'IP2', 'FAMILY2', 'TYPE2']])
        socket_impl.stub(:sockaddr_in)
          .with('PORT', 'IP1')
          .and_return('SOCKADDR1')
        socket_impl.stub(:sockaddr_in)
          .with('PORT', 'IP2')
          .and_return('SOCKADDR2')
        socket_impl.stub(:new)
          .with('FAMILY1', 'TYPE1', 0)
          .and_return(socket)
        socket_impl.stub(:new)
          .with('FAMILY2', 'TYPE2', 0)
          .and_return(socket)
        socket.stub(:close)
        socket.stub(:bind)
        socket.stub(:listen)
      end

      describe '#bind' do
        if RUBY_ENGINE == 'jruby'
          it 'creates a new socket and binds it to all interfaces' do
            acceptor.bind
            socket.should have_received(:bind).with('SOCKADDR1', backlog)
          end

          it 'tries the next address when the first one raises EADDRNOTAVAIL' do
            socket.stub(:bind).with('SOCKADDR1', anything).and_raise(Errno::EADDRNOTAVAIL)
            acceptor.bind
            socket.should have_received(:bind).with('SOCKADDR2', backlog)
          end
        else
          it 'creates a new socket and binds it to all interfaces' do
            acceptor.bind
            socket.should have_received(:bind).with('SOCKADDR1')
            socket.should have_received(:listen).with(backlog)
          end

          it 'tries the next address when the first one raises EADDRNOTAVAIL' do
            socket.stub(:bind).with('SOCKADDR1').and_raise(Errno::EADDRNOTAVAIL)
            acceptor.bind
            socket.should have_received(:bind).with('SOCKADDR2')
            socket.should have_received(:listen).with(backlog)
          end
        end

        it 'returns a failed future when none of the addresses worked' do
          socket.stub(:bind).and_raise(Errno::EADDRNOTAVAIL)
          f = acceptor.bind
          expect { f.value }.to raise_error(Errno::EADDRNOTAVAIL)
        end

        it 'closes the socket when none of the addresses worked' do
          socket.stub(:bind).and_raise(Errno::EADDRNOTAVAIL)
          acceptor.bind.value rescue nil
          socket.should have_received(:close)
        end

        it 'returns a future that resolves to itself when the socket has been bound' do
          f = acceptor.bind
          f.should be_resolved
          f.value.should equal(acceptor)
        end
      end

      describe '#close' do
        before do
          socket.stub(:close)
        end

        it 'closes the socket' do
          acceptor.bind
          acceptor.close
          socket.should have_received(:close)
        end

        it 'does nothing when called before #bind' do
          acceptor.close
        end

        it 'does nothing when called again' do
          acceptor.bind
          acceptor.close
          acceptor.close
          acceptor.close
        end

        it 'ignores IOError' do
          socket.stub(:close).and_raise(IOError)
          acceptor.bind
          expect { acceptor.close }.to_not raise_error
        end

        it 'ignores Errno::*' do
          socket.stub(:close).and_raise(Errno::EINVAL)
          acceptor.bind
          expect { acceptor.close }.to_not raise_error
        end

        it 'is closed afterwards' do
          acceptor.bind
          acceptor.close
          acceptor.should be_closed
        end

        it 'is is not connected afterwards' do
          acceptor.bind
          acceptor.close
          acceptor.should_not be_connected
        end
      end

      describe '#read' do
        include_context 'accepting_connections'

        it 'accepts a new connection' do
          acceptor.bind
          acceptor.read
          socket.should have_received(:accept_nonblock)
        end

        it 'creates a new connection handler and registers it with the reactor' do
          acceptor.bind
          acceptor.read
          accepted_handlers.should have(1).item
          accepted_handlers.first.host.should == 'example.com'
          accepted_handlers.first.port.should == 3333
        end

        it 'passes the unblocker along to the connection handler' do
          unblocker.stub(:unblock!)
          acceptor.bind
          acceptor.read
          accepted_handlers.first.write('foo')
          unblocker.should have_received(:unblock!)
        end
      end

      describe '#on_accept' do
        include_context 'accepting_connections'

        it 'calls accept listeners with new connections' do
          received_connection1 = nil
          received_connection2 = nil
          acceptor.on_accept { |c| received_connection1 = c }
          acceptor.on_accept { |c| received_connection2 = c }
          acceptor.bind
          acceptor.read
          received_connection1.host.should == 'example.com'
          received_connection2.host.should == 'example.com'
          received_connection2.port.should == 3333
        end

        it 'ignores exceptions raised by the connection callback' do
          called = false
          acceptor.on_accept { |c| raise 'bork!' }
          acceptor.on_accept { |c| called = true }
          acceptor.bind
          acceptor.read
          called.should be_true
        end
      end

      describe '#to_io' do
        it 'returns the socket' do
          acceptor.bind
          acceptor.to_io.should equal(socket)
        end

        it 'returns nil when the socket has been closed' do
          socket.stub(:close)
          acceptor.bind
          acceptor.close
          acceptor.to_io.should be_nil
        end
      end
    end
  end
end
