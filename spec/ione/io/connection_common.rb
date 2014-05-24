# encoding: utf-8

shared_examples_for 'a connection' do |options|
  describe '#close' do
    it 'closes the socket' do
      socket.should_receive(:close)
      handler.close
    end

    it 'returns true' do
      handler.close.should be_true
    end

    it 'does nothing when called again' do
      handler.close
      handler.close
      handler.close
    end

    it 'swallows SystemCallErrors' do
      socket.stub(:close).and_raise(SystemCallError.new('Bork!', 9999))
      handler.close
    end

    it 'swallows IOErrors' do
      socket.stub(:close).and_raise(IOError.new('Bork!'))
      handler.close
    end

    it 'calls the closed listener' do
      called = false
      handler.on_closed { called = true }
      handler.close
      called.should be_true, 'expected the close listener to have been called'
    end

    it 'does nothing when closed a second time' do
      socket.should_receive(:close).once
      calls = 0
      handler.on_closed { calls += 1 }
      handler.close
      handler.close
      calls.should == 1
    end

    it 'returns false if it did nothing' do
      handler.close
      handler.close.should be_false
    end

    it 'is not writable when closed' do
      handler.write('foo')
      handler.close
      handler.should_not be_writable
    end

    it 'is closed afterwards' do
      handler.close
      handler.should be_closed
    end

    it 'is is not connected afterwards' do
      handler.close
      handler.should_not be_connected
    end
  end

  describe '#drain' do
    before do
      socket.stub(:write_nonblock) { |s| s.bytesize }
    end

    it 'waits for the buffer to drain and then closes the socket' do
      handler.write('hello world')
      handler.drain
      handler.should_not be_closed
      handler.flush
      handler.should be_closed
    end

    it 'closes the socket immediately when the buffer is empty' do
      handler.drain
      handler.should be_closed
    end

    it 'returns a future that completes when the socket has closed' do
      handler.write('hello world')
      f = handler.drain
      f.should_not be_completed
      handler.flush
      f.should be_completed
    end
  end

  describe '#write/#flush' do
    before do
      socket.stub(:write_nonblock)
      unblocker.stub(:unblock!)
    end

    it 'appends to its buffer when #write is called' do
      handler.write('hello world')
    end

    it 'unblocks the reactor' do
      unblocker.should_receive(:unblock!)
      handler.write('hello world')
    end

    it 'is writable when there are bytes to write' do
      handler.should_not be_writable
      handler.write('hello world')
      handler.should be_writable
      socket.should_receive(:write_nonblock).with('hello world').and_return(11)
      handler.flush
      handler.should_not be_writable
    end

    it 'writes to the socket from its buffer when #flush is called' do
      handler.write('hello world')
      socket.should_receive(:write_nonblock).with('hello world').and_return(11)
      handler.flush
    end

    it 'takes note of how much the #write_nonblock call consumed and writes the rest of the buffer on the next call to #flush' do
      handler.write('hello world')
      socket.should_receive(:write_nonblock).with('hello world').and_return(6)
      handler.flush
      socket.should_receive(:write_nonblock).with('world').and_return(5)
      handler.flush
    end

    it 'does not call #write_nonblock if the buffer is empty' do
      handler.flush
      handler.write('hello world')
      socket.should_receive(:write_nonblock).with('hello world').and_return(11)
      handler.flush
      socket.should_not_receive(:write_nonblock)
      handler.flush
    end

    context 'with a block' do
      it 'yields a byte buffer to the block' do
        socket.should_receive(:write_nonblock).with('hello world').and_return(11)
        handler.write do |buffer|
          buffer << 'hello world'
        end
        handler.flush
      end
    end

    context 'when #write_nonblock raises an error' do
      before do
        socket.stub(:close)
        socket.stub(:write_nonblock).and_raise('Bork!')
      end

      it 'closes the socket' do
        socket.should_receive(:close)
        handler.write('hello world')
        handler.flush
      end

      it 'passes the error to the close handler' do
        error = nil
        handler.on_closed { |e| error = e }
        handler.write('hello world')
        handler.flush
        error.should be_a(Exception)
      end
    end

    context 'when closed' do
      it 'discards the bytes' do
        handler.close
        handler.write('hello world')
        handler.flush
        socket.should_not have_received(:write_nonblock)
      end

      it 'does not yield the buffer' do
        called = false
        handler.close
        handler.write { called = true }
        handler.flush
        called.should be_false
      end

      it 'does not unblock the reactor' do
        handler.close
        handler.write('hello world')
        handler.flush
        unblocker.should_not have_received(:unblock!)
      end
    end

    context 'when draining' do
      it 'discards the bytes' do
        handler.drain
        handler.write('hello world')
        handler.flush
        socket.should_not have_received(:write_nonblock)
      end

      it 'does not yield the buffer' do
        called = false
        handler.drain
        handler.write { called = true }
        handler.flush
        called.should be_false
      end

      it 'does not unblock the reactor' do
        handler.drain
        handler.write('hello world')
        handler.flush
        unblocker.should_not have_received(:unblock!)
      end
    end
  end

  if options.nil? || options.fetch(:skip_read, false) == false
    describe '#read/#on_data' do
      it 'reads a chunk from the socket' do
        socket.should_receive(:read_nonblock).with(instance_of(Fixnum)).and_return('foo bar')
        handler.read
      end

      it 'calls the data listener with the new data' do
        socket.should_receive(:read_nonblock).with(instance_of(Fixnum)).and_return('foo bar')
        data = nil
        handler.on_data { |d| data = d }
        handler.read
        data.should == 'foo bar'
      end

      context 'when #read_nonblock raises an error' do
        before do
          socket.stub(:close)
          socket.stub(:read_nonblock).and_raise('Bork!')
        end

        it 'closes the socket' do
          socket.should_receive(:close)
          handler.read
        end

        it 'passes the error to the close handler' do
          error = nil
          handler.on_closed { |e| error = e }
          handler.read
          error.should be_a(Exception)
        end
      end
    end
  end
end
