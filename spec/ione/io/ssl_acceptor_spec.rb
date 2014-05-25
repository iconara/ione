# encoding: utf-8

require 'spec_helper'


module Ione
  module Io
    describe SslAcceptor do
      let :acceptor do
        described_class.new('example.com', 4321, backlog = 3, unblocker, reactor, ssl_context, socket_impl, ssl_socket_impl)
      end

      let :unblocker do
        double(:unblocker)
      end

      let :reactor do
        double(:reactor)
      end

      let :ssl_context do
        double(:ssl_context)
      end

      let :socket_impl do
        double(:socket_impl)
      end

      let :ssl_socket_impl do
        double(:ssl_socket_impl)
      end

      let :socket do
        double(:socket)
      end

      let :ssl_socket do
        double(:ssl_socket)
      end

      let :client_socket do
        double(:client_socket)
      end

      describe '#read' do
        let :accepted_handlers do
          []
        end

        before do
          socket_impl.stub(:getaddrinfo).and_return([[nil, 'PORT', nil, 'IP1', 'FAMILY1', 'TYPE1']])
          socket_impl.stub(:sockaddr_in).with('PORT', 'IP1').and_return('SOCKADDRX')
          socket_impl.stub(:unpack_sockaddr_in).with('SOCKADDRX').and_return([3333, 'example.com'])
          socket_impl.stub(:new).and_return(socket)
          socket.stub(:bind)
          socket.stub(:listen)
          socket.stub(:accept_nonblock).and_return([client_socket, 'SOCKADDRX'])
          reactor.stub(:accept) { |h| accepted_handlers << h }
          ssl_socket_impl.stub(:new).with(client_socket, ssl_context).and_return(ssl_socket)
          ssl_socket.stub(:accept_nonblock)
        end

        it 'accepts a new connection' do
          acceptor.bind
          acceptor.read
          socket.should have_received(:accept_nonblock)
        end

        it 'notifies the accept handlers' do
          connection = nil
          acceptor.on_accept { |c| connection = c }
          acceptor.bind
          acceptor.read
          accepted_handlers.first.read
          connection.should equal(accepted_handlers.first)
        end

        context 'creates a new connection handler that' do
          it 'is registered it with the reactor' do
            acceptor.bind
            acceptor.read
            accepted_handlers.should have(1).item
            accepted_handlers.first.host.should == 'example.com'
            accepted_handlers.first.port.should == 3333
          end

          it 'returns the raw socket from #to_io' do
            ssl_socket.stub(:to_io).and_return(client_socket)
            acceptor.bind
            acceptor.read
            accepted_handlers.first.to_io.should equal(client_socket)
          end

          it 'has a reference to the unblocker' do
            unblocker.stub(:unblock!)
            acceptor.bind
            acceptor.read
            accepted_handlers.first.write('foo')
            unblocker.should have_received(:unblock!)
          end

          it 'writes to the SSL socket' do
            unblocker.stub(:unblock!)
            ssl_socket.stub(:write_nonblock) { |b| b.bytesize }
            acceptor.bind
            acceptor.read
            accepted_handlers.first.read
            accepted_handlers.first.write('foo')
            accepted_handlers.first.flush
            ssl_socket.should have_received(:write_nonblock).with('foo')
          end
        end
      end
    end
  end
end
