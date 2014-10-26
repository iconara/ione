# encoding: utf-8

require 'thread'


module Ione
  FutureError = Class.new(StandardError)

  # A promise of delivering a value some time in the future.
  #
  # A promise is the write end of a Promise/Future pair. It can be fulfilled
  # with a value or failed with an error. The value can be read through the
  # future returned by {#future}.
  class Promise
    attr_reader :future

    def initialize
      @future = CompletableFuture.new
    end

    # Fulfills the promise.
    #
    # This will resolve this promise's future, and trigger all listeners of that
    # future. The value of the future will be the specified value, or nil if
    # no value is specified.
    #
    # @param [Object] value the value of the future
    def fulfill(value=nil)
      @future.resolve(value)
    end

    # Fails the promise.
    #
    # This will fail this promise's future, and trigger all listeners of that
    # future.
    #
    # @param [Error] error the error which prevented the promise to be fulfilled
    def fail(error)
      @future.fail(error)
    end

    # Observe a future and fulfill the promise with the future's value when the
    # future resolves, or fail with the future's error when the future fails.
    #
    # @param [Ione::Future] future the future to observe
    def observe(future)
      future.on_complete do |v, e|
        if e
          fail(e)
        else
          fulfill(v)
        end
      end
    end

    # Run the given block and fulfill this promise with its result. If the block
    # raises an error, fail this promise with the error.
    #
    # All arguments given will be passed onto the block.
    #
    # @example
    #   promise.try { 3 + 4 }
    #   promise.future.value # => 7
    #
    # @example
    #   promise.try do
    #     do_something_that_will_raise_an_error
    #   end
    #   promise.future.value # => (raises error)
    #
    # @example
    #   promise.try('foo', 'bar', &proc_taking_two_arguments)
    #
    # @yieldparam [Array] ctx the arguments passed to {#try}
    def try(*ctx)
      fulfill(yield(*ctx))
    rescue => e
      fail(e)
    end
  end

  module FutureFactories
    # Combines multiple futures into a new future which resolves when all
    # constituent futures complete, or fails when one or more of them fails.
    #
    # The value of the combined future is an array of the values of the
    # constituent futures.
    #
    # @param [Array<Ione::Future>] futures the futures to combine (this argument
    #   can be a splatted array or a regular array passed as sole argument)
    # @return [Ione::Future<Array>] an array of the values of the constituent
    #   futures
    def all(*futures)
      if futures.size == 1 && (fs = futures.first).is_a?(Enumerable)
        futures = fs
      end
      if futures.count == 0
        resolved([])
      else
        CombinedFuture.new(futures)
      end
    end

    # Returns a future which will be resolved with the value of the first
    # (resolved) of the specified futures. If all of the futures fail, the
    # returned future will also fail (with the error of the last failed future).
    #
    # @param [Array<Ione::Future>] futures the futures to monitor (this argument
    #   can be a splatted array or a regular array passed as sole argument)
    # @return [Ione::Future] a future which represents the first completing future
    def first(*futures)
      return resolved if futures.empty?
      futures = futures.size == 1 && futures.first.is_a?(Enumerable) ? futures.first : futures
      return futures.first if futures.is_a?(Array) && futures.size == 1
      FirstFuture.new(futures)
    end

    # Takes calls the block once for each element in an array, expecting each
    # invocation to return a future, and returns a future that resolves to
    # an array of the values of those futures.
    #
    # @example
    #   ids = [1, 2, 3]
    #   future = Future.traverse(ids) { |id| load_thing(id) }
    #   future.value # => [thing1, thing2, thing3]
    #
    # @param [Array<Object>] values an array whose elements will be passed to
    #   the block, one by one
    # @yieldparam [Object] value each element from the array
    # @yieldreturn [Ione::Future] a future
    # @return [Ione::Future] a future that will resolve to an array of the values
    #   of the futures returned by the block
    def traverse(values, &block)
      all(values.map(&block))
    rescue => e
      failed(e)
    end

    # Returns a future that will resolve to a value which is the reduction of
    # the values of a list of source futures.
    #
    # This is essentially a parallel, streaming version of {Enumerable#reduce},
    # but for futures. Use this method for example when you want to do a number
    # of asynchronous operations in parallel and then merge the results together
    # when all are done.
    #
    # The block will not be called concurrently, which means that unless you're
    # handling the initial value or other values in the scope of the block you
    # don't need (and shouldn't) do any locking to ensure that the accumulator
    # passed to the block is safe to modify. It is, of course, even better if
    # you don't modify the accumulator, but return a new, immutable value on
    # each invocation.
    #
    # @example Merging the results of multipe asynchronous calls
    #   futures = ... # a list of futures that will resolve to hashes
    #   merged_future = Future.reduce(futures, {}) do |accumulator, value|
    #     accumulator.merge(value)
    #   end
    #
    # @example Reducing with an associative and commutative function, like addition
    #   futures = ... # a list of futures that will resolve to numbers
    #   sum_future = Future.reduce(futures, 0, ordered: false) do |accumulator, value|
    #     accumulator + value
    #   end
    #
    # @param [Array<Ione::Future>] futures an array of futures whose values
    #   should be reduced
    # @param [Object] initial_value the initial value of the accumulator
    # @param [Hash] options
    # @option options [Boolean] :ordered (true) whether or not to respect the
    #   order of the input when reducing – when true the block will be called
    #   with the values of the source futures in the order they have in the
    #   given list, when false the block will be called in the order that the
    #   futures resolve (which means that your reducer function needs to be
    #   associative and commutative).
    # @yieldparam [Object] accumulator the value of the last invocation of the
    #   block, or the initial value if this is the first invocation
    # @yieldparam [Object] value the value of one of the source futures
    # @yieldreturn [Object] the value to pass as accumulator to the next
    #   invocation of the block
    # @return [Ione::Future] a future that will resolve to the value returned
    #   from the last invocation of the block, or nil when the list of futures
    #   is empty.
    def reduce(futures, initial_value=nil, options=nil, &reducer)
      if options && options[:ordered] == false
        UnorderedReducingFuture.new(futures, initial_value, reducer)
      else
        OrderedReducingFuture.new(futures, initial_value, reducer)
      end
    end

    # Creates a new pre-resolved future.
    #
    # @param [Object, nil] value the value of the created future
    # @return [Ione::Future] a resolved future
    def resolved(value=nil)
      return ResolvedFuture::NIL if value.nil?
      ResolvedFuture.new(value)
    end

    # Creates a new pre-failed future.
    #
    # @param [Error] error the error of the created future
    # @return [Ione::Future] a failed future
    def failed(error)
      FailedFuture.new(error)
    end
  end

  module FutureCombinators
    # Returns a new future representing a transformation of this future's value.
    #
    # @example
    #   future2 = future1.map { |value| value * 2 }
    #
    # @param [Object] value the value of this future (when no block is given)
    # @yieldparam [Object] value the value of this future
    # @yieldreturn [Object] the transformed value
    # @return [Ione::Future] a new future representing the transformed value
    def map(value=nil, &block)
      f = CompletableFuture.new
      on_complete do |v, e|
        if e
          f.fail(e)
        else
          begin
            f.resolve(block ? block.call(v) : value)
          rescue => e
            f.fail(e)
          end
        end
      end
      f
    end

    # Returns a new future representing a transformation of this future's value,
    # but where the transformation itself may be asynchronous.
    #
    # @example
    #   future2 = future1.flat_map { |value| method_returning_a_future(value) }
    #
    # This method is useful when you want to chain asynchronous operations.
    #
    # @yieldparam [Object] value the value of this future
    # @yieldreturn [Ione::Future] a future representing the transformed value
    # @return [Ione::Future] a new future representing the transformed value
    def flat_map(&block)
      f = CompletableFuture.new
      on_complete do |v, e|
        if e
          f.fail(e)
        else
          begin
            ff = block.call(v)
            ff.on_complete do |vv, ee|
              if ee
                f.fail(ee)
              else
                f.resolve(vv)
              end
            end
          rescue => e
            f.fail(e)
          end
        end
      end
      f
    end

    # Returns a new future representing a transformation of this future's value,
    # similarily to {#map}, but acts as {#flat_map} when the block returns a
    # {Future}.
    #
    # This method is useful when you want to transform the value of a future,
    # but whether or not it can be done synchronously or require an asynchronous
    # operation depends on the value of the future.
    #
    # @example
    #   future1 = load_something
    #   future2 = future1.then do |result|
    #     if result.empty?
    #       # make a new async call to load fallback value
    #       load_something_else
    #     else
    #       result
    #     end
    #   end
    #
    # @yieldparam [Object] value the value of this future
    # @yieldreturn [Object, Ione::Future] the transformed value, or a future
    #   that will resolve to the transformed value.
    # @return [Ione::Future] a new future representing the transformed value
    def then(&block)
      f = CompletableFuture.new
      on_complete do |v, e|
        if e
          f.fail(e)
        else
          begin
            fv = block.call(v)
            if fv.respond_to?(:on_complete)
              fv.on_complete do |vv, ee|
                if ee
                  f.fail(ee)
                else
                  f.resolve(vv)
                end
              end
            else
              f.resolve(fv)
            end
          rescue => e
            f.fail(e)
          end
        end
      end
      f
    end

    # Returns a new future which represents either the value of the original
    # future, or the result of the given block, if the original future fails.
    #
    # This method is similar to {#map}, but is triggered by a failure. You can
    # also think of it as a `rescue` block for asynchronous operations.
    #
    # If the block raises an error a failed future with that error will be
    # returned (this can be used to transform an error into another error,
    # instead of tranforming an error into a value).
    #
    # @example
    #   future2 = future1.recover { |error| 'foo' }
    #   future1.fail(error)
    #   future2.value # => 'foo'
    #
    # @param [Object] value the value when no block is given
    # @yieldparam [Object] error the error from the original future
    # @yieldreturn [Object] the value of the new future
    # @return [Ione::Future] a new future representing a value recovered from the error
    def recover(value=nil, &block)
      f = CompletableFuture.new
      on_complete do |v, e|
        if e
          begin
            f.resolve(block ? block.call(e) : value)
          rescue => e
            f.fail(e)
          end
        else
          f.resolve(v)
        end
      end
      f
    end

    # Returns a new future which represents either the value of the original
    # future, or the value of the future returned by the given block.
    #
    # This is like {#recover} but for cases when the handling of an error is
    # itself asynchronous. In other words, {#fallback} is to {#recover} what
    # {#flat_map} is to {#map}.
    #
    # If the block raises an error a failed future with that error will be
    # returned (this can be used to transform an error into another error,
    # instead of tranforming an error into a value).
    #
    # @example
    #   result = http_get('/foo/bar').fallback do |error|
    #     http_get('/baz')
    #   end
    #   result.value # either the response to /foo/bar, or if that failed
    #                # the response to /baz
    #
    # @yieldparam [Object] error the error from the original future
    # @yieldreturn [Object] the value of the new future
    # @return [Ione::Future] a new future representing a value recovered from the
    #   error
    def fallback(&block)
      f = CompletableFuture.new
      on_complete do |v, e|
        if e
          begin
            ff = block.call(e)
            ff.on_complete do |vv, ee|
              if ee
                f.fail(ee)
              else
                f.resolve(vv)
              end
            end
          rescue => e
            f.fail(e)
          end
        else
          f.resolve(v)
        end
      end
      f
    end
  end

  module FutureCallbacks
    # Registers a listener that will be called when this future becomes
    # resolved. The listener will be called with the value of the future as
    # sole argument.
    #
    # @yieldparam [Object] value the value of the resolved future
    def on_value(&listener)
      on_complete do |value, error|
        listener.call(value) unless error
      end
      nil
    end

    # Registers a listener that will be called when this future fails. The
    # lisener will be called with the error that failed the future as sole
    # argument.
    #
    # @yieldparam [Error] error the error that failed the future
    def on_failure(&listener)
      on_complete do |_, error|
        listener.call(error) if error
      end
      nil
    end
  end

  # A future represents the value of a process that may not yet have completed.
  #
  # @see Ione::Promise
  class Future
    extend FutureFactories
    include FutureCombinators
    include FutureCallbacks

    def initialize
      @lock = Mutex.new
      @state = :pending
      @listeners = []
    end

    # Registers a listener that will be called when this future completes,
    # i.e. resolves or fails. The listener will be called with the future as
    # solve argument
    #
    # @yieldparam [Ione::Future] future the future
    def on_complete(&listener)
      run_immediately = false
      if @state != :pending
        run_immediately = true
      else
        @lock.lock
        begin
          if @state == :pending
            @listeners << listener
          else
            run_immediately = true
          end
        ensure
          @lock.unlock
        end
      end
      if run_immediately
        call_listener(listener)
      end
      nil
    end

    # Returns the value of this future, blocking until it is available if
    # necessary.
    #
    # If the future fails this method will raise the error that failed the
    # future.
    #
    # @return [Object] the value of this future
    def value
      raise @error if @state == :failed
      return @value if @state == :resolved
      semaphore = nil
      @lock.lock
      begin
        raise @error if @state == :failed
        return @value if @state == :resolved
        semaphore = Queue.new
        u = proc { semaphore << :unblock }
        @listeners << u
      ensure
        @lock.unlock
      end
      while true
        @lock.lock
        begin
          raise @error if @state == :failed
          return @value if @state == :resolved
        ensure
          @lock.unlock
        end
        semaphore.pop
      end
    end
    alias_method :get, :value

    # Returns true if this future is resolved or failed
    def completed?
      return true unless @state == :pending
      @lock.lock
      begin
        @state != :pending
      ensure
        @lock.unlock
      end
    end

    # Returns true if this future is resolved
    def resolved?
      return @state == :resolved unless @state == :pending
      @lock.lock
      begin
        @state == :resolved
      ensure
        @lock.unlock
      end
    end

    # Returns true if this future has failed
    def failed?
      return @state == :failed unless @state == :pending
      @lock.lock
      begin
        @state == :failed
      ensure
        @lock.unlock
      end
    end

    private

    def call_listener(listener)
      begin
        n = listener.arity
        if n == 1
          listener.call(self)
        elsif n == 2 || n == -3
          listener.call(@value, @error)
        elsif n == 0
          listener.call
        else
          listener.call(@value, @error, self)
        end
      rescue
        # swallowed
      end
    end
  end

  # @private
  class CompletableFuture < Future
    def resolve(v=nil)
      listeners = nil
      @lock.lock
      begin
        raise FutureError, 'Future already completed' unless @state == :pending
        @value = v
        @state = :resolved
        listeners = @listeners
        @listeners = nil
      ensure
        @lock.unlock
      end
      listeners.each do |listener|
        call_listener(listener)
      end
      nil
    end

    def fail(error)
      listeners = nil
      @lock.lock
      begin
        raise FutureError, 'Future already completed' unless @state == :pending
        @error = error
        @state = :failed
        listeners = @listeners
        @listeners = nil
      ensure
        @lock.unlock
      end
      listeners.each do |listener|
        call_listener(listener)
      end
      nil
    end
  end

  # @private
  class CombinedFuture < CompletableFuture
    def initialize(futures)
      super()
      remaining = futures.count
      values = Array.new(remaining)
      futures.each_with_index do |f, i|
        f.on_complete do |v, e|
          unless failed?
            if e
              fail(e)
            else
              @lock.lock
              begin
                values[i] = v
                remaining -= 1
              ensure
                @lock.unlock
              end
              if remaining == 0
                resolve(values)
              end
            end
          end
        end
      end
    end
  end

  # @private
  class ReducingFuture < CompletableFuture
    def initialize(futures, initial_value, reducer)
      super()
      @futures = Array(futures)
      @remaining = @futures.size
      @initial_value = initial_value
      @accumulator = initial_value
      @reducer = reducer
    end

    private

    def reduce_one(value)
      unless failed?
        @lock.lock
        begin
          if @accumulator
            @accumulator = @reducer.call(@accumulator, value)
          else
            @accumulator = value
          end
          @remaining -= 1
        rescue => e
          @lock.unlock
          fail(e)
        else
          @lock.unlock
        end
        unless failed?
          if @remaining == 0
            resolve(@accumulator)
            :done
          else
            :continue
          end
        end
      end
    end
  end

  # @private
  class OrderedReducingFuture < ReducingFuture
    def initialize(futures, initial_value, reducer)
      super
      if @remaining > 0
        reduce_next(0)
      else
        resolve(@initial_value)
      end
    end

    private

    def reduce_next(i)
      @futures[i].on_complete do |v, e|
        unless failed?
          if e
            fail(e)
          elsif reduce_one(v) == :continue
            reduce_next(i + 1)
          end
        end
      end
    end
  end

  # @private
  class UnorderedReducingFuture < ReducingFuture
    def initialize(futures, initial_value, reducer)
      super
      if @remaining > 0
        futures.each do |f|
          f.on_complete do |v, e|
            unless failed?
              if e
                fail(e)
              else
                reduce_one(v)
              end
            end
          end
        end
      else
        resolve(@initial_value)
      end
    end
  end

  # @private
  class FirstFuture < CompletableFuture
    def initialize(futures)
      super()
      futures.each do |f|
        f.on_complete do |v, e|
          unless completed?
            if e
              if futures.all?(&:failed?)
                fail(e)
              end
            else
              resolve(v)
            end
          end
        end
      end
    end
  end

  # @private
  class ResolvedFuture < Future
    def initialize(value=nil)
      @state = :resolved
      @value = value
      @error = nil
    end

    def value
      @value
    end

    def completed?
      true
    end

    def resolved?
      true
    end

    def failed?
      false
    end

    def on_complete(&listener)
      call_listener(listener)
    end

    def on_value(&listener)
      listener.call(value) rescue nil
    end

    def on_failure
    end

    NIL = new(nil)
  end

  # @private
  class FailedFuture < Future
    def initialize(error)
      @state = :failed
      @value = nil
      @error = error
    end

    def value
      raise @error
    end

    def completed?
      true
    end

    def resolved?
      false
    end

    def failed?
      true
    end

    def on_complete(&listener)
      call_listener(listener)
    end

    def on_value
    end

    def on_failure(&listener)
      listener.call(@error) rescue nil
    end
  end
end
