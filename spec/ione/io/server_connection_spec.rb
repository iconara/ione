# encoding: utf-8

require 'spec_helper'


module Ione
  module Io
    describe ServerConnection do
      let :connection_handler do
        described_class.new(socket, 'example.com', 4321, unblocker)
      end

      let :socket do
        double(:socket)
      end

      let :unblocker do
        double(:unblocker)
      end

      describe '#close' do
        before do
          socket.stub(:close)
        end

        it 'closes the socket' do
          connection_handler.close
          socket.should have_received(:close)
        end

        it 'does nothing when called again' do
          connection_handler.close
          connection_handler.close
          connection_handler.close
        end

        it 'ignores IOError' do
          socket.stub(:close).and_raise(IOError)
          expect { connection_handler.close }.to_not raise_error
        end

        it 'ignores Errno::*' do
          socket.stub(:close).and_raise(Errno::EINVAL)
          expect { connection_handler.close }.to_not raise_error
        end

        it 'is closed afterwards' do
          connection_handler.close
          connection_handler.should be_closed
        end

        it 'is is not connected afterwards' do
          connection_handler.close
          connection_handler.should_not be_connected
        end

        it 'calls the closed listener' do
          called = false
          connection_handler.on_closed { called = true }
          connection_handler.close
          called.should be_true
        end
      end

      describe '#write/#writable?/#flush' do
        before do
          unblocker.stub(:unblock!)
          socket.stub(:write_nonblock) { |data| data.bytesize }
          socket.stub(:close)
        end

        it 'makes #writable? return true' do
          connection_handler.write('foo')
          connection_handler.should be_writable
        end

        it 'unblocks the reactor' do
          connection_handler.write('foo')
          unblocker.should have_received(:unblock!)
        end

        it 'flushes what has been written to the socket' do
          connection_handler.write('foo')
          connection_handler.flush
          socket.should have_received(:write_nonblock).with('foo')
        end

        it 'flushes only what the socket accepts, flushing the rest on the next call' do
          socket.stub(:write_nonblock).with('foo').and_return(2)
          connection_handler.write('foo')
          connection_handler.flush
          connection_handler.flush
          socket.should have_received(:write_nonblock).with('foo')
          socket.should have_received(:write_nonblock).with('o')
        end

        it 'yields its buffer' do
          connection_handler.write { |buffer| buffer << 'foo' }
          connection_handler.should be_writable
          connection_handler.flush
          socket.should have_received(:write_nonblock).with('foo')
        end

        it 'closes the socket when an error is raised' do
          socket.stub(:write_nonblock).and_raise(StandardError.new('BOOORK'))
          error = nil
          connection_handler.on_closed { |e| error = e }
          connection_handler.write('foo')
          connection_handler.flush
          connection_handler.should be_closed
          error.message.should == 'BOOORK'
        end
      end

      describe '#read/#on_data' do
        it 'reads a chunk of data from the socket and delivers it to the data listener' do
          socket.stub(:read_nonblock).and_return('helloworld')
          data = nil
          connection_handler.on_data { |d| data = d }
          connection_handler.read
          data.should == 'helloworld'
        end

        it 'closes the socket when an error is raised' do
          socket.stub(:read_nonblock).and_raise(StandardError.new('BOOORK'))
          socket.stub(:close)
          error = nil
          connection_handler.on_closed { |e| error = e }
          connection_handler.read
          error.message.should == 'BOOORK'
        end
      end

      describe '#to_io' do
        it 'returns the socket' do
          connection_handler.to_io.should equal(socket)
        end

        it 'returns nil when the socket is closed' do
          socket.stub(:close)
          connection_handler.close
          connection_handler.to_io.should be_nil
        end
      end
    end
  end
end
