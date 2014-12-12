# encoding: utf-8

require 'spec_helper'


module Ione
  describe Promise do
    let :promise do
      described_class.new
    end

    let :future do
      promise.future
    end

    let :error do
      StandardError.new('bork')
    end

    describe '#fulfill' do
      it 'resolves its future' do
        promise.fulfill
        future.should be_resolved
      end

      it 'raises an error if fulfilled a second time' do
        promise.fulfill
        expect { promise.fulfill }.to raise_error(FutureError)
      end

      it 'raises an error if failed after being fulfilled' do
        promise.fulfill
        expect { promise.fail(error) }.to raise_error(FutureError)
      end

      it 'returns nil' do
        promise.fulfill(:foo).should be_nil
      end
    end

    describe '#fail' do
      it 'fails its future' do
        promise.fail(error)
        future.should be_failed
      end

      it 'raises an error if failed a second time' do
        promise.fail(error)
        expect { promise.fail(error) }.to raise_error(FutureError)
      end

      it 'raises an error if fulfilled after being failed' do
        promise.fail(error)
        expect { promise.fulfill }.to raise_error(FutureError)
      end

      it 'returns nil' do
        promise.fail(error).should be_nil
      end
    end

    describe '#observe' do
      it 'resolves its future when the specified future is resolved' do
        p2 = Promise.new
        promise.observe(p2.future)
        p2.fulfill
        promise.future.should be_resolved
      end

      it 'fails its future when the specified future fails' do
        p2 = Promise.new
        promise.observe(p2.future)
        p2.fail(error)
        promise.future.should be_failed
      end

      it 'silently ignores double fulfillment/failure' do
        p2 = Promise.new
        promise.observe(p2.future)
        promise.fail(error)
        p2.fulfill
      end

      it 'returns nil' do
        promise.observe(Promise.new.future).should be_nil
      end
    end

    describe '#try' do
      it 'fulfills the promise with the result of the block' do
        promise.try do
          3 + 4
        end
        promise.future.value.should == 7
      end

      it 'fails the promise when the block raises an error' do
        promise.try do
          raise error
        end
        expect { promise.future.value }.to raise_error(/bork/)
      end

      it 'calls the block with the specified arguments' do
        promise.try(:foo, 3) do |a, b|
          a.length + b
        end
        promise.future.value.should == 6
      end

      it 'returns nil' do
        promise.try { }.should be_nil
      end
    end
  end

  describe Future do
    let :promise do
      Promise.new
    end

    let :future do
      promise.future
    end

    let :error do
      StandardError.new('bork')
    end

    def async(*context, &listener)
      Thread.start(*context, &listener)
    end

    def delayed(*context, &listener)
      async(*context) do |*ctx|
        sleep(0.1)
        listener.call(*context)
      end
    end

    describe '#completed?' do
      it 'is true when the promise is fulfilled' do
        promise.fulfill
        future.should be_completed
      end

      it 'is true when the promise is failed' do
        promise.fail(StandardError.new('bork'))
        future.should be_completed
      end

      it 'is false before the future has been resolved or failed' do
        future.should_not be_completed
      end
    end

    describe '#resolved?' do
      it 'is true when the promise is fulfilled' do
        promise.fulfill('foo')
        future.should be_resolved
      end

      it 'is true when the promise is fulfilled with something falsy' do
        promise.fulfill(nil)
        future.should be_resolved
      end

      it 'is false when the promise is failed' do
        promise.fail(StandardError.new('bork'))
        future.should_not be_resolved
      end

      it 'is false before the future has been resolved or failed' do
        future.should_not be_resolved
      end
    end

    describe '#failed?' do
      it 'is true when the promise is failed' do
        promise.fail(error)
        future.should be_failed
      end

      it 'is false when the promise is fulfilled' do
        promise.fulfill
        future.should_not be_failed
      end

      it 'is false before the future has been resolved or failed' do
        future.should_not be_failed
      end
    end

    describe '#on_complete' do
      context 'registers listeners and' do
        it 'notifies all listeners when the promise is fulfilled' do
          c1, c2 = false, false
          future.on_complete { c1 = true }
          future.on_complete { c2 = true }
          promise.fulfill('bar')
          c1.should be_true
          c2.should be_true
        end

        it 'passes the future as the first parameter to the block' do
          f1, f2 = nil, nil
          future.on_complete { |f| f1 = f }
          future.on_complete { |f| f2 = f }
          promise.fulfill('bar')
          f1.should equal(future)
          f2.should equal(future)
        end

        it 'passes the value as the first parameter to the block when it expects two arguments' do
          v1, v2 = nil, nil
          future.on_complete { |v, _| v1 = v }
          future.on_complete { |v, _| v2 = v }
          promise.fulfill('bar')
          v1.should == 'bar'
          v2.should == 'bar'
        end

        it 'passes future as the third parameter to the block when it expects three arguments' do
          f1, f2 = nil, nil
          future.on_complete { |_, _, f| f1 = f }
          future.on_complete { |_, _, f| f2 = f }
          promise.fulfill('bar')
          f1.should equal(future)
          f2.should equal(future)
        end

        it 'passes the value, error and future to the block when it expects any number of arguments' do
          value = 'bar'
          error = StandardError.new('bork')
          args1, args2 = nil, nil
          p1 = Promise.new
          p2 = Promise.new
          p1.future.on_complete { |*a| args1 = a }
          p2.future.on_complete { |*a| args2 = a }
          p1.fulfill(value)
          p2.fail(error)
          args1[0].should equal(value)
          args1[1].should be_nil
          args1[2].should equal(p1.future)
          args2[0].should be_nil
          args2[1].should equal(error)
          args2[2].should equal(p2.future)
        end

        it 'passes the value, error and future to the listener when the listener is a lambda' do
          value = 'bar'
          error = StandardError.new('bork')
          args1, args2 = nil, nil
          p1 = Promise.new
          p2 = Promise.new
          p1.future.on_complete(&lambda { |v, e, f| args1 = [v, e, f] })
          p2.future.on_complete(&lambda { |v, e, f| args2 = [v, e, f] })
          p1.fulfill(value)
          p2.fail(error)
          args1[0].should equal(value)
          args1[1].should be_nil
          args1[2].should equal(p1.future)
          args2[0].should be_nil
          args2[1].should equal(error)
          args2[2].should equal(p2.future)
        end

        it 'ignores optional arguments for lambdas' do
          value = 'bar'
          error = StandardError.new('bork')
          args1, args2 = nil, nil
          p1 = Promise.new
          p2 = Promise.new
          p1.future.on_complete(&lambda { |v, e, f=nil| args1 = [v, e, f] })
          p2.future.on_complete(&lambda { |v, e, f, x=1, y=2| args2 = [v, e, f, x, y] })
          p1.fulfill(value)
          p2.fail(error)
          args1[0].should equal(value)
          args1[1].should be_nil
          args1[2].should be_nil
          args2[0].should be_nil
          args2[1].should equal(error)
          args2[2].should equal(p2.future)
        end

        it 'does not handle listeners that are lambdas and have one optional argument' do
          pending 'MRI 1.9.3 thinks these lambas have arity 1 and not -2' if RUBY_ENGINE == 'ruby' && RUBY_VERSION < '2.0.0'
          called1, called2 = false, false
          p1 = Promise.new
          p2 = Promise.new
          p1.future.on_complete(&lambda { |v, e=nil| called1 = true })
          p2.future.on_complete(&lambda { |v, e=nil| called2 = true })
          p1.fulfill('bar')
          p2.fail(StandardError.new('bork'))
          called1.should be_false
          called2.should be_false
        end

        it 'notifies all listeners when the promise fails' do
          c1, c2 = nil, nil
          future.on_complete { c1 = true }
          future.on_complete { c2 = true }
          future.fail(error)
          c1.should be_true
          c2.should be_true
        end

        it 'passes the error as the second parameter to the block when it expects two arguments' do
          e1, e2 = nil, nil
          future.on_complete { |_, e| e1 = e }
          future.on_complete { |_, e| e2 = e }
          future.fail(error)
          e1.should equal(error)
          e2.should equal(error)
        end

        it 'notifies all listeners when the promise is fulfilled, even when one raises an error' do
          value = nil
          future.on_complete { |f| raise 'Blurgh' }
          future.on_complete { |f| value = f.value }
          promise.fulfill('bar')
          value.should == 'bar'
        end

        it 'notifies all listeners when the promise fails, even when one raises an error' do
          err = nil
          future.on_complete { |f| raise 'Blurgh' }
          future.on_complete { |f| begin; f.value; rescue => err; e = err; end }
          promise.fail(error)
          err.message.should == 'bork'
        end

        it 'notifies listeners registered after the promise was fulfilled' do
          f, v, e = nil, nil, nil
          promise.fulfill('bar')
          future.on_complete { |vv, ee, ff| v = vv; e = ee; f = ff }
          f.should equal(future)
          v.should == 'bar'
          e.should be_nil
        end

        it 'notifies listeners registered after the promise failed' do
          f, v, e = nil, nil, nil
          promise.fail(StandardError.new('bork'))
          future.on_complete { |vv, ee, ff| v = vv; e = ee; f = ff }
          f.should equal(future)
          v.should be_nil
          e.message.should == 'bork'
        end

        it 'notifies listeners registered after the promise failed' do
          promise.fail(error)
          expect { future.on_complete { raise 'blurgh' } }.to_not raise_error
        end

        it 'returns nil' do
          future.on_complete { :foo }.should be_nil
        end

        it 'returns nil when the future is already resolved' do
          promise.fulfill
          future.on_complete { :foo }.should be_nil
        end

        it 'returns nil when the future already has failed' do
          promise.fail(error)
          future.on_complete { :foo }.should be_nil
        end
      end
    end

    describe '#on_value' do
      context 'registers listeners and' do
        it 'notifies all value listeners when the promise is fulfilled' do
          v1, v2 = nil, nil
          future.on_value { |v| v1 = v }
          future.on_value { |v| v2 = v }
          promise.fulfill('bar')
          v1.should == 'bar'
          v2.should == 'bar'
        end

        it 'notifies all listeners even when one raises an error' do
          value = nil
          future.on_value { |v| raise 'Blurgh' }
          future.on_value { |v| value = v }
          promise.fulfill('bar')
          value.should == 'bar'
        end

        it 'notifies listeners registered after the promise was resolved' do
          v1, v2 = nil, nil
          promise.fulfill('bar')
          future.on_value { |v| v1 = v }
          future.on_value { |v| v2 = v }
          v1.should == 'bar'
          v2.should == 'bar'
        end

        it 'does not raise any error when the listener raises an error when already resolved' do
          promise.fulfill('bar')
          expect { future.on_value { |v| raise 'blurgh' } }.to_not raise_error
        end

        it 'returns nil' do
          future.on_value { :foo }.should be_nil
        end

        it 'returns nil when the future is already resolved' do
          promise.fulfill
          future.on_failure { :foo }.should be_nil
        end
      end
    end

    describe '#on_failure' do
      context 'registers listeners and' do
        it 'notifies all failure listeners when the promise fails' do
          e1, e2 = nil, nil
          future.on_failure { |err| e1 = err }
          future.on_failure { |err| e2 = err }
          promise.fail(error)
          e1.message.should eql(error.message)
          e2.message.should eql(error.message)
        end

        it 'notifies all listeners even if one raises an error' do
          e = nil
          future.on_failure { |err| raise 'Blurgh' }
          future.on_failure { |err| e = err }
          promise.fail(error)
          e.message.should eql(error.message)
        end

        it 'notifies new listeners even when already failed' do
          e1, e2 = nil, nil
          promise.fail(error)
          future.on_failure { |e| e1 = e }
          future.on_failure { |e| e2 = e }
          e1.message.should eql(error.message)
          e2.message.should eql(error.message)
        end

        it 'does not raise any error when the listener raises an error when already failed' do
          promise.fail(error)
          expect { future.on_failure { |e| raise 'Blurgh' } }.to_not raise_error
        end

        it 'returns nil' do
          future.on_failure { :foo }.should be_nil
        end

        it 'returns nil when the future already has failed' do
          promise.fail(error)
          future.on_failure { :foo }.should be_nil
        end
      end
    end

    describe '#value' do
      it 'is nil by default' do
        promise.fulfill
        future.value.should be_nil
      end

      it 'is the object passed to Promise#fulfill' do
        obj = 'hello world'
        promise.fulfill(obj)
        future.value.should equal(obj)
      end

      it 'raises the error passed to Promise#fail' do
        promise.fail(StandardError.new('bork'))
        expect { future.value }.to raise_error(/bork/)
      end

      it 'blocks until the promise is completed' do
        d = delayed(promise) do |p|
          p.fulfill('bar')
        end
        d.value
        future.value.should == 'bar'
      end

      it 'blocks on #value until completed, when value is nil' do
        d = delayed(promise) do |p|
          p.fulfill
        end
        d.value
        future.value.should be_nil
      end

      it 'blocks on #value until failed' do
        d = delayed(promise) do |p|
          p.fail(StandardError.new('bork'))
        end
        d.value
        expect { future.value }.to raise_error('bork')
      end

      it 'allows multiple threads to block on #value until completed' do
        listeners = Array.new(10) do
          async(future) do |f|
            f.value
          end
        end
        sleep 0.1
        promise.fulfill(:hello)
        listeners.map(&:value).should == Array.new(10, :hello)
      end

      it 'is aliased as #get' do
        obj = 'hello world'
        promise.fulfill(obj)
        future.get.should equal(obj)
      end
    end

    describe '#map' do
      context 'when the future eventually resolves' do
        context 'returns a future that' do
          it 'will be resolved with the result of the given block' do
            p = Promise.new
            f = p.future.map { |v| v * 2 }
            p.fulfill(3)
            f.value.should == 3 * 2
          end

          it 'will be resolved with the specified value' do
            p = Promise.new
            f = p.future.map(7)
            p.fulfill(3)
            f.value.should == 7
          end

          it 'will be resolved with the result of the given block, even if a value is specified' do
            p = Promise.new
            f = p.future.map(7) { |v| v * 2 }
            p.fulfill(3)
            f.value.should == 3 * 2
          end

          it 'will be resolved with nil when neither value nor block is specified' do
            p = Promise.new
            f = p.future.map
            p.fulfill(3)
            f.value.should be_nil
          end

          it 'fails when the block raises an error' do
            p = Promise.new
            f = p.future.map { |v| raise 'Blurgh' }
            d = delayed do
              p.fulfill
            end
            d.value
            expect { f.value }.to raise_error('Blurgh')
          end
        end
      end

      context 'when the future eventually fails' do
        it 'returns a future that fails' do
          p = Promise.new
          f = p.future.map { |v| v * 2 }
          p.fail(StandardError.new('Blurgh'))
          expect { f.value }.to raise_error('Blurgh')
        end

        it 'does not call the block' do
          called = false
          p = Promise.new
          f = p.future.map { called = true }
          p.fail(StandardError.new('Blurgh'))
          called.should be_false
        end
      end

      context 'when the future is already resolved' do
        context 'returns a future that' do
          it 'will be resolved with the result of the given block' do
            f = Future.resolved(3).map { |v| v * 2 }
            f.value.should == 3 * 2
          end

          it 'will be resolved with the specified value' do
            f = Future.resolved(3).map(7)
            f.value.should == 7
          end

          it 'will be resolved with the result of the given block, even if a value is specified' do
            f = Future.resolved(3).map(7) { |v| v * 2 }
            f.value.should == 3 * 2
          end

          it 'will be resolved with nil when neither value nor block is specified' do
            f = Future.resolved(3).map
            f.value.should be_nil
          end

          it 'fails when the block raises an error' do
            f = Future.resolved(3).map { |v| raise 'Blurgh' }
            expect { f.value }.to raise_error('Blurgh')
          end
        end
      end

      context 'when the future is already failed' do
        it 'does not call the block' do
          called = false
          Future.failed(StandardError.new('Hurgh')).map { called = true }
          called.should be_false
        end

        it 'returns a future that fails' do
          f = Future.failed(StandardError.new('Hurgh')).map { 3 }
          f.should be_failed
        end
      end
    end

    describe '#flat_map' do
      context 'when the future eventually resolves' do
        it 'passes the value of the source future to the block, and resolves to the value of the future returned by the block' do
          p = Promise.new
          f = p.future.flat_map { |v| Future.resolved(v * 2) }
          p.fulfill(3)
          f.value.should == 3 * 2
        end

        it 'fails when the block raises an error' do
          p = Promise.new
          f = p.future.flat_map { |v| raise 'Hurgh' }
          p.fulfill(3)
          expect { f.value }.to raise_error('Hurgh')
        end

        it 'fails when the block returns a failed future' do
          p = Promise.new
          f = p.future.flat_map { |v| Future.failed(StandardError.new('Hurgh')) }
          p.fulfill(3)
          expect { f.value }.to raise_error('Hurgh')
        end

        it 'fails when the block returns a future that eventually fails' do
          p1 = Promise.new
          p2 = Promise.new
          f = p1.future.flat_map { |v| p2.future }
          p1.fulfill(3)
          p2.fail(StandardError.new('Hurgh'))
          expect { f.value }.to raise_error('Hurgh')
        end
      end

      context 'when the future eventually fails' do
        it 'returns a future that fails' do
          p = Promise.new
          f = p.future.flat_map { |v| Future.resolved(v) }
          p.fail(StandardError.new('Hurgh'))
          f.should be_failed
        end

        it 'does not call the block' do
          called = false
          p = Promise.new
          f = p.future.flat_map { called = true }
          p.fail(StandardError.new('Hurgh'))
          called.should be_false
        end
      end

      context 'when the future is already resolved' do
        it 'passes the value of the source future to the block, and resolves to the value of the future returned by the block' do
          f = Future.resolved(3).flat_map { |v| Future.resolved(v * 2) }
          f.value.should == 3 * 2
        end

        it 'fails when the block raises an error' do
          f = Future.resolved(3).flat_map { |v| raise 'Hurgh' }
          expect { f.value }.to raise_error('Hurgh')
        end

        it 'fails when the block returns a failed future' do
          f = Future.resolved(3).flat_map { |v| Future.failed(StandardError.new('Hurgh')) }
          expect { f.value }.to raise_error('Hurgh')
        end

        it 'fails when the block returns a future that eventually fails' do
          p = Promise.new
          f = Future.resolved(3).flat_map { |v| p.future }
          p.fail(StandardError.new('Hurgh'))
          expect { f.value }.to raise_error('Hurgh')
        end
      end

      context 'when the future is already failed' do
        it 'does not call the block' do
          called = false
          Future.failed(StandardError.new('Hurgh')).flat_map { called = true }
          called.should be_false
        end

        it 'returns a future that fails' do
          f = Future.failed(StandardError.new('Hurgh')).flat_map { |v| Future.resolved(v) }
          f.should be_failed
        end
      end

      it 'accepts anything that implements #on_complete as a chained future' do
        fake_future = double(:fake_future)
        fake_future.stub(:on_complete) { |&listener| listener.call(:foobar, nil) }
        p = Promise.new
        f = p.future.flat_map { fake_future }
        p.fulfill
        f.value.should == :foobar
      end
    end

    describe '#then' do
      context 'when the block returns a future' do
        context 'and the receiving future eventually resolves' do
          it 'passes the value of the source future to the block, and resolves to the value of the future returned by the block' do
            p = Promise.new
            f = p.future.then { |v| Future.resolved(v * 2) }
            p.fulfill(3)
            f.value.should == 3 * 2
          end

          it 'fails when the block raises an error' do
            p = Promise.new
            f = p.future.then { |v| raise 'Hurgh' }
            p.fulfill(3)
            expect { f.value }.to raise_error('Hurgh')
          end

          it 'fails when the block returns a failed future' do
            p = Promise.new
            f = p.future.then { |v| Future.failed(StandardError.new('Hurgh')) }
            p.fulfill(3)
            expect { f.value }.to raise_error('Hurgh')
          end

          it 'fails when the block returns a future that eventually fails' do
            p1 = Promise.new
            p2 = Promise.new
            f = p1.future.then { |v| p2.future }
            p1.fulfill(3)
            p2.fail(StandardError.new('Hurgh'))
            expect { f.value }.to raise_error('Hurgh')
          end
        end

        context 'and the receiving future eventually fails' do
          it 'returns a future that fails' do
            p = Promise.new
            f = p.future.then { |v| Future.resolved(v) }
            p.fail(StandardError.new('Hurgh'))
            f.should be_failed
          end

          it 'does not call the block' do
            called = false
            p = Promise.new
            f = p.future.then { called = true }
            p.fail(StandardError.new('Hurgh'))
            called.should be_false
          end
        end

        context 'and the receiving future is already resolved' do
          it 'passes the value of the source future to the block, and resolves to the value of the future returned by the block' do
            f = Future.resolved(3).then { |v| Future.resolved(v * 2) }
            f.value.should == 3 * 2
          end

          it 'fails when the block raises an error' do
            f = Future.resolved(3).then { |v| raise 'Hurgh' }
            expect { f.value }.to raise_error('Hurgh')
          end

          it 'fails when the block returns a failed future' do
            f = Future.resolved(3).then { |v| Future.failed(StandardError.new('Hurgh')) }
            expect { f.value }.to raise_error('Hurgh')
          end

          it 'fails when the block returns a future that eventually fails' do
            p = Promise.new
            f = Future.resolved(3).then { |v| p.future }
            p.fail(StandardError.new('Hurgh'))
            expect { f.value }.to raise_error('Hurgh')
          end
        end

        context 'and the receiving future is already failed' do
          it 'does not call the block' do
            called = false
            Future.failed(StandardError.new('Hurgh')).then { called = true }
            called.should be_false
          end

          it 'returns a future that fails' do
            f = Future.failed(StandardError.new('Hurgh')).then { |v| Future.resolved(v) }
            f.should be_failed
          end
        end
      end

      context 'when the block returns something that quacks like a future' do
        context 'and yields a value from #on_complete' do
          it 'works like #flat_map' do
            fake_future = double(:fake_future)
            fake_future.stub(:on_complete) { |&listener| listener.call(:foobar) }
            p = Promise.new
            f = p.future.then { |v| fake_future }
            p.fulfill
            f.value.should == :foobar
          end
        end

        context 'and yields an error from #on_complete' do
          it 'works like #flat_map' do
            fake_future = double(:fake_future)
            fake_future.stub(:on_complete) { |&listener| listener.call(nil, StandardError.new('bork')) }
            p = Promise.new
            f = p.future.then { |v| fake_future }
            p.fulfill
            expect { f.value }.to raise_error(StandardError, 'bork')
          end
        end
      end

      context 'when the block returns something that does not quack like a future' do
        context 'and the receiving future eventually resolves' do
          context 'returns a future that' do
            it 'will be resolved with the result of the given block' do
              p = Promise.new
              f = p.future.then { |v| v * 2 }
              p.fulfill(3)
              f.value.should == 3 * 2
            end

            it 'fails when the block raises an error' do
              p = Promise.new
              f = p.future.then { |v| raise 'Blurgh' }
              d = delayed do
                p.fulfill
              end
              d.value
              expect { f.value }.to raise_error('Blurgh')
            end
          end
        end

        context 'and the receiving future eventually fails' do
          it 'returns a future that fails' do
            p = Promise.new
            f = p.future.then { |v| v * 2 }
            p.fail(StandardError.new('Blurgh'))
            expect { f.value }.to raise_error('Blurgh')
          end

          it 'does not call the block' do
            called = false
            p = Promise.new
            f = p.future.then { called = true }
            p.fail(StandardError.new('Blurgh'))
            called.should be_false
          end
        end

        context 'and the receiving future is already resolved' do
          context 'returns a future that' do
            it 'will be resolved with the result of the given block' do
              f = Future.resolved(3).then { |v| v * 2 }
              f.value.should == 3 * 2
            end

            it 'fails when the block raises an error' do
              f = Future.resolved(3).then { |v| raise 'Blurgh' }
              expect { f.value }.to raise_error('Blurgh')
            end
          end
        end

        context 'when the future is already failed' do
          it 'does not call the block' do
            called = false
            Future.failed(StandardError.new('Hurgh')).map { called = true }
            called.should be_false
          end

          it 'returns a future that fails' do
            f = Future.failed(StandardError.new('Hurgh')).map { 3 }
            f.should be_failed
          end
        end
      end
    end

    describe '#recover' do
      context 'when the future will eventually resolve' do
        it 'does not call the block' do
          called = false
          p = Promise.new
          p.future.recover { called = true }
          p.fulfill(3)
          called.should be_false
        end

        it 'returns a future that resolves' do
          p = Promise.new
          f = p.future.recover { 7 }
          p.fulfill(3)
          f.value.should == 3
        end
      end

      context 'when the future will eventually fail' do
        it 'resolves to a value created by the block' do
          p = Promise.new
          f = p.future.recover { 'foo' }
          p.fail(error)
          f.value.should == 'foo'
        end

        it 'resolves to a specfied value' do
          p = Promise.new
          f = p.future.recover('bar')
          p.fail(error)
          f.value.should == 'bar'
        end

        it 'resovles to a value created by the block even when a value is specified' do
          p = Promise.new
          f = p.future.recover('bar') { 'foo' }
          p.fail(error)
          f.value.should == 'foo'
        end

        it 'resolves to nil value when no value nor block is specified' do
          p = Promise.new
          f = p.future.recover
          p.fail(error)
          f.value.should be_nil
        end

        it 'yields the error to the block' do
          p = Promise.new
          f = p.future.recover { |e| e.message }
          p.fail(error)
          f.value.should == error.message
        end

        it 'fails with the error raised in the given block' do
          p = Promise.new
          f = p.future.recover { raise 'snork' }
          p.fail(StandardError.new('bork'))
          expect { f.value }.to raise_error('snork')
        end
      end

      context 'when the future is already resolved' do
        it 'does not call the block' do
          called = false
          Future.resolved(3).recover { called = true }
          called.should be_false
        end

        it 'returns a future that resolves' do
          f = Future.resolved(3).recover { 7 }
          f.value.should == 3
        end
      end

      context 'when the future is already failed' do
        it 'resolves to a value created by the block' do
          f = Future.failed(StandardError.new('bork')).recover { 'foo' }
          f.value.should == 'foo'
        end

        it 'resolves to a specfied value when the source future fails' do
          f =  Future.failed(StandardError.new('bork')).recover('bar')
          f.value.should == 'bar'
        end

        it 'resovles to a value created by the block even when a value is specified when the source future fails' do
          f =  Future.failed(StandardError.new('bork')).recover('bar') { 'foo' }
          f.value.should == 'foo'
        end

        it 'resolves to nil value when no value nor block is specified and the source future fails' do
          f =  Future.failed(StandardError.new('bork')).recover
          f.value.should be_nil
        end

        it 'yields the error to the block' do
          f =  Future.failed(StandardError.new('bork')).recover { |e| e.message }
          f.value.should == error.message
        end

        it 'fails with the error raised in the given block' do
          f =  Future.failed(StandardError.new('bork')).recover { raise 'snork' }
          expect { f.value }.to raise_error('snork')
        end
      end
    end

    describe '#fallback' do
      context 'when the future eventually resolves' do
        it 'is resolved with the value of the source future' do
          p1 = Promise.new
          p2 = Promise.new
          f = p1.future.fallback { p2.future }
          p2.fulfill('bar')
          p1.fulfill('foo')
          f.value.should == 'foo'
        end

        it 'does not call the block' do
          called = false
          p = Promise.new
          f = p.future.fallback { called = true }
          p.fulfill('foo')
          called.should be_false
        end
      end

      context 'when the future eventually fails' do
        it 'is resolved with the value of the fallback future' do
          p1 = Promise.new
          p2 = Promise.new
          f = p1.future.fallback { p2.future }
          p1.fail(error)
          p2.fulfill('foo')
          f.value.should == 'foo'
        end

        it 'yields the error to the block' do
          p1 = Promise.new
          p2 = Promise.new
          f = p1.future.fallback do |error|
            Future.resolved(error.message)
          end
          p1.fail(error)
          f.value.should == error.message
        end

        it 'fails when the block raises an error' do
          p = Promise.new
          f = p.future.fallback { raise 'bork' }
          p.fail(StandardError.new('splork'))
          expect { f.value }.to raise_error('bork')
        end

        it 'fails when the fallback future fails' do
          p1 = Promise.new
          p2 = Promise.new
          f = p1.future.fallback { p2.future }
          p2.fail(StandardError.new('bork'))
          p1.fail(StandardError.new('fnork'))
          expect { f.value }.to raise_error('bork')
        end
      end

      context 'when the future is already resolved' do
        it 'is resolved with the value of the source future' do
          f = Future.resolved('foo').fallback { Future.resolved('bar') }
          f.value.should == 'foo'
        end

        it 'does not call the block' do
          called = false
          f = Future.resolved('foo').fallback { called = true }
          called.should be_false
        end
      end

      context 'when the future is already failed' do
        it 'is resolved with the value of the fallback future' do
          f = Future.failed(StandardError.new('bork')).fallback { Future.resolved('foo') }
          f.value.should == 'foo'
        end

        it 'yields the error to the block' do
          f = Future.failed(StandardError.new('bork')).fallback do |error|
            Future.resolved(error.message)
          end
          f.value.should == 'bork'
        end

        it 'fails when the block raises an error' do
          f = Future.failed(StandardError.new('bork')).fallback { raise 'snork' }
          expect { f.value }.to raise_error('snork')
        end

        it 'fails when the fallback future fails' do
          f = Future.failed(StandardError.new('bork')).fallback { Future.failed(StandardError.new('snork')) }
          expect { f.value }.to raise_error('snork')
        end
      end

      it 'accepts anything that implements #on_complete as a fallback future' do
        fake_future = double(:fake_future)
        fake_future.stub(:on_complete) { |&listener| listener.call('foo', nil) }
        p = Promise.new
        f = p.future.fallback { fake_future }
        p.fail(error)
        f.value.should == 'foo'
      end
    end

    describe '.traverse' do
      it 'combines Array#map and Future.all' do
        future = Future.traverse([1, 2, 3]) do |element|
          Future.resolved(element * 2)
        end
        future.value.should == [2, 4, 6]
      end

      it 'fails if any of the source futures fail' do
        future = Future.traverse([1, 2, 3]) do |element|
          if element == 2
            Future.failed(StandardError.new('BORK'))
          else
            Future.resolved(element * 2)
          end
        end
        future.should be_failed
      end

      it 'fails if any of the block invocations fail' do
        future = Future.traverse([1, 2, 3]) do |element|
          if element == 2
            raise 'BORK'
          else
            Future.resolved(element * 2)
          end
        end
        future.should be_failed
      end

      it 'accepts anything that implements #on_complete as futures' do
        fake_future = double(:fake_future)
        fake_future.stub(:on_complete) { |&listener| listener.call(:foobar, nil) }
        future = Future.traverse([1, 2, 3]) { fake_future }
        future.value.should == [:foobar, :foobar, :foobar]
      end

      it 'accepts an enumerable of values' do
        future = Future.traverse([1, 2, 3].to_enum) { |v| Future.resolved(v * 2) }
        future.value.should == [2, 4, 6]
      end
    end

    describe '.reduce' do
      it 'returns a future which represents the value of reducing the values of the inputs' do
        futures = [
          Future.resolved({'foo' => 'bar'}),
          Future.resolved({'qux' => 'baz'}),
          Future.resolved({'hello' => 'world'})
        ]
        future = Future.reduce(futures, {}) do |accumulator, value|
          accumulator.merge(value)
        end
        future.value.should == {'foo' => 'bar', 'qux' => 'baz', 'hello' => 'world'}
      end

      it 'calls the block with the values in the order of the source futures' do
        promises = [Promise.new, Promise.new, Promise.new, Promise.new, Promise.new]
        futures = promises.map(&:future)
        future = Future.reduce(futures, []) do |accumulator, value|
          accumulator.push(value)
        end
        promises[1].fulfill(1)
        promises[0].fulfill(0)
        promises[2].fulfill(2)
        promises[4].fulfill(4)
        promises[3].fulfill(3)
        future.value.should == [0, 1, 2, 3, 4]
      end

      it 'uses the first value as initial value when no intial value is given' do
        promises = [Promise.new, Promise.new, Promise.new]
        futures = promises.map(&:future)
        future = Future.reduce(futures) do |sum, n|
          sum + n
        end
        promises[1].fulfill(2)
        promises[0].fulfill(1)
        promises[2].fulfill(3)
        future.value.should == 6
      end

      it 'fails if any of the source futures fail' do
        futures = [Future.resolved(0), Future.failed(StandardError.new('BORK')), Future.resolved(2)]
        future = Future.reduce(futures, []) do |accumulator, value|
          accumulator.push(value)
        end
        future.should be_failed
      end

      it 'fails if any of the block invocations fail' do
        futures = [Future.resolved(0), Future.resolved(1), Future.resolved(2)]
        future = Future.reduce(futures, []) do |accumulator, value|
          if value == 2
            raise 'BORK'
          else
            accumulator.push(value)
          end
        end
        future.should be_failed
      end

      context 'when the list of futures is empty' do
        it 'returns a future that resolves to the initial value' do
          Future.reduce([], :foo).value.should == :foo
        end

        it 'returns a future that resolves to nil there is also no initial value' do
          Future.reduce([]).value.should be_nil
        end
      end

      it 'accepts anything that implements #on_complete as futures' do
        ff1, ff2, ff3 = double, double, double
        ff1.stub(:on_complete) { |&listener| listener.call(1, nil) }
        ff2.stub(:on_complete) { |&listener| listener.call(2, nil) }
        ff3.stub(:on_complete) { |&listener| listener.call(3, nil) }
        future = Future.reduce([ff1, ff2, ff3], 0) { |sum, n| sum + n }
        future.value.should == 6
      end

      it 'accepts an enumerable of futures' do
        futures = [Future.resolved(1), Future.resolved(2), Future.resolved(3)].to_enum
        future = Future.reduce(futures, 0) { |sum, n| sum + n }
        future.value.should == 6
      end

      context 'when the :ordered option is false' do
        it 'calls the block with the values in the order of completion, when the :ordered option is false' do
          promises = [Promise.new, Promise.new, Promise.new]
          futures = promises.map(&:future)
          future = Future.reduce(futures, [], ordered: false) do |accumulator, value|
            accumulator.push(value)
          end
          promises[1].fulfill(1)
          promises[0].fulfill(0)
          promises[2].fulfill(2)
          future.value.should == [1, 0, 2]
        end

        it 'fails if any of the source futures fail' do
          futures = [Future.resolved(0), Future.failed(StandardError.new('BORK')), Future.resolved(2)]
          future = Future.reduce(futures, [], ordered: false) do |accumulator, value|
            accumulator.push(value)
          end
          future.should be_failed
        end

        it 'fails if any of the block invocations fail' do
          futures = [Future.resolved(0), Future.resolved(1), Future.resolved(2)]
          future = Future.reduce(futures, [], ordered: false) do |accumulator, value|
            if value == 1
              raise 'BORK'
            else
              accumulator.push(value)
            end
          end
          future.should be_failed
        end

        context 'when the list of futures is empty' do
          it 'returns a future that resolves to the initial value' do
            Future.reduce([], :foo, ordered: false).value.should == :foo
          end

          it 'returns a future that resolves to nil there is also no initial value' do
            Future.reduce([], nil, ordered: false).value.should be_nil
          end
        end
      end
    end

    describe '.all' do
      context 'returns a new future which' do
        it 'is resolved when the source futures are resolved' do
          p1 = Promise.new
          p2 = Promise.new
          f = Future.all(p1.future, p2.future)
          p1.fulfill
          f.should_not be_resolved
          p2.fulfill
          f.should be_resolved
        end

        it 'returns an array of the values of the source futures, in order' do
          p1 = Promise.new
          p2 = Promise.new
          p3 = Promise.new
          f = Future.all(p1.future, p2.future, p3.future)
          p2.fulfill(2)
          p1.fulfill(1)
          p3.fulfill(3)
          f.value.should == [1, 2, 3]
        end

        it 'fails if any of the source futures fail' do
          p1 = Promise.new
          p2 = Promise.new
          p3 = Promise.new
          p4 = Promise.new
          f = Future.all(p1.future, p2.future, p3.future, p4.future)
          p2.fulfill
          p1.fail(StandardError.new('hurgh'))
          p3.fail(StandardError.new('murgasd'))
          p4.fulfill
          expect { f.value }.to raise_error('hurgh')
          f.should be_failed
        end

        it 'completes with an empty list when no futures are given' do
          Future.all.value.should == []
        end

        it 'completes with an empty list when an empty list is given' do
          Future.all([]).value.should == []
        end

        it 'completes with an empty list when an empty enumerable is given' do
          Future.all([].to_enum).value.should == []
        end

        it 'completes with a list of one item when a single future is given' do
          f = Future.resolved(1)
          Future.all(f).value.should == [1]
        end

        it 'accepts a list of futures' do
          promises = [Promise.new, Promise.new, Promise.new]
          futures = promises.map(&:future)
          f = Future.all(futures)
          promises.each(&:fulfill)
          f.value.should have(3).items
        end

        it 'accepts an enumerable of futures' do
          promises = [Promise.new, Promise.new, Promise.new]
          futures = promises.map(&:future).to_enum
          f = Future.all(futures)
          promises.each(&:fulfill)
          f.value.should have(3).items
        end

        it 'accepts an enumerable of one future' do
          promises = [Promise.new]
          futures = promises.map(&:future).to_enum
          f = Future.all(futures)
          promises.each(&:fulfill)
          f.value.should have(1).item
        end

        it 'accepts anything that implements #on_complete as futures' do
          ff1, ff2, ff3 = double, double, double
          ff1.stub(:on_complete) { |&listener| listener.call(1, nil) }
          ff2.stub(:on_complete) { |&listener| listener.call(2, nil) }
          ff3.stub(:on_complete) { |&listener| listener.call(3, nil) }
          future = Future.all(ff1, ff2, ff3)
          future.value.should == [1, 2, 3]
        end
      end
    end

    describe '.first' do
      context 'it returns a new future which' do
        it 'is resolved when the first of the source futures is resolved' do
          p1 = Promise.new
          p2 = Promise.new
          p3 = Promise.new
          f = Future.first(p1.future, p2.future, p3.future)
          p2.fulfill
          f.should be_resolved
        end

        it 'fullfills with the value of the first source future' do
          p1 = Promise.new
          p2 = Promise.new
          p3 = Promise.new
          f = Future.first(p1.future, p2.future, p3.future)
          p2.fulfill('foo')
          f.value.should == 'foo'
        end

        it 'is unaffected by the fullfillment of the other futures' do
          p1 = Promise.new
          p2 = Promise.new
          p3 = Promise.new
          f = Future.first(p1.future, p2.future, p3.future)
          p2.fulfill
          p1.fulfill
          p3.fulfill
          f.value
        end

        it 'is unaffected by a future failing when at least one resolves' do
          p1 = Promise.new
          p2 = Promise.new
          p3 = Promise.new
          f = Future.first(p1.future, p2.future, p3.future)
          p2.fail(error)
          p1.fail(error)
          p3.fulfill
          expect { f.value }.to_not raise_error
        end

        it 'fails if all of the source futures fail' do
          p1 = Promise.new
          p2 = Promise.new
          p3 = Promise.new
          f = Future.first(p1.future, p2.future, p3.future)
          p2.fail(error)
          p1.fail(error)
          p3.fail(error)
          f.should be_failed
        end

        it 'fails with the error of the last future to fail' do
          p1 = Promise.new
          p2 = Promise.new
          p3 = Promise.new
          f = Future.first(p1.future, p2.future, p3.future)
          p2.fail(StandardError.new('bork2'))
          p1.fail(StandardError.new('bork1'))
          p3.fail(StandardError.new('bork3'))
          expect { f.value }.to raise_error('bork3')
        end

        it 'completes with nil when no futures are given' do
          Future.first.value.should be_nil
        end

        it 'completes with the value of the given future, when only one is given' do
          Future.first(Future.resolved('foo')).value.should == 'foo'
        end

        it 'accepts a list of futures' do
          promises = [Promise.new, Promise.new, Promise.new]
          futures = promises.map(&:future)
          f = Future.first(futures)
          promises.each(&:fulfill)
          f.should be_resolved
        end

        it 'accepts an enumerable of futures' do
          promises = [Promise.new, Promise.new, Promise.new]
          futures = promises.map(&:future).to_enum
          f = Future.first(futures)
          promises.each(&:fulfill)
          f.should be_resolved
        end

        it 'accepts anything that implements #on_complete as futures' do
          ff1, ff2 = double, double
          ff1.stub(:on_complete) { |&listener| listener.call(1, nil) }
          ff2.stub(:on_complete) { |&listener| listener.call(2, nil) }
          future = Future.first(ff1, ff2)
          future.value.should == 1
        end
      end
    end

    describe '.resolved' do
      context 'returns a future which' do
        let :future do
          described_class.resolved('hello world')
        end

        it 'is resolved' do
          future.should be_resolved
        end

        it 'is completed' do
          future.should be_completed
        end

        it 'is not failed' do
          future.should_not be_failed
        end

        it 'calls its value callbacks immediately' do
          value = nil
          future.on_value { |v| value = v }
          value.should == 'hello world'
        end

        it 'calls its complete callbacks immediately' do
          f, v = nil, nil
          future.on_complete { |vv, _, ff| f = ff; v = vv }
          f.should equal(future)
          v.should == 'hello world'
        end

        it 'calls its complete callbacks with the right arity' do
          f1, v, f2 = nil, nil, nil
          future.on_complete { |ff| f1 = ff }
          future.on_complete { |vv, ee| v = vv }
          future.on_complete { |vv, ee, ff| f2 = ff }
          f1.should equal(future)
          f2.should equal(future)
          v.should == 'hello world'
        end

        it 'does not block on #value' do
          future.value.should == 'hello world'
        end

        it 'defaults to the value nil' do
          described_class.resolved.value.should be_nil
        end
      end
    end

    describe '.failed' do
      let :future do
        described_class.failed(error)
      end

      context 'returns a future which' do
        it 'is failed' do
          future.should be_failed
        end

        it 'is completed' do
          future.should be_completed
        end

        it 'is not resolved' do
          future.should_not be_resolved
        end

        it 'call its failure callbacks immediately' do
          error = nil
          future.on_failure { |e| error = e }
          error.message.should == 'bork'
        end

        it 'calls its complete callbacks immediately' do
          f, e = nil, nil
          future.on_complete { |_, ee, ff| f = ff; e = ee }
          f.should equal(future)
          e.message.should == 'bork'
        end

        it 'calls its complete callbacks with the right arity' do
          f1, e, f2 = nil, nil, nil
          future.on_complete { |ff| f1 = ff }
          future.on_complete { |vv, ee| e = ee }
          future.on_complete { |vv, ee, ff| f2 = ff }
          f1.should equal(future)
          f2.should equal(future)
          e.message.should == 'bork'
        end

        it 'does not block on #value' do
          expect { future.value }.to raise_error('bork')
        end
      end
    end
  end
end
