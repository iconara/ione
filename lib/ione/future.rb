# encoding: utf-8

require 'thread'


module Ione
  FutureError = Class.new(StandardError)

  # A promise of delivering a value some time in the future.
  #
  # A promise is the write end of a Promise/Future pair. It can be fulfilled
  # with a value or failed with an error. The value can be read through the
  # future returned by {#future}.
  # @since v1.0.0
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
      @future.observe(future)
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
    def try(*ctx, &block)
      @future.try(*ctx, &block)
    end
  end

  # A future represents the value of a process that may not yet have completed.
  #
  # A future is either pending or completed and there are two ways to complete a
  # future: either by resolving it to a value, or by failing it.
  #
  # A future is usually created by first creating a {Promise} and returning that
  # promise's future to the caller. The promise can then be _fulfilled_ which
  # resolves the future – see below for an example of thi.
  #
  # The key thing about futures is that they _compose_. If you have a future
  # you can transform it and combine without waiting for its value to be
  # available. This means that you can model a series of asynchronous operations
  # without worrying about which order they will complete in, or what happens
  # if any of them fail. You can describe the steps you want to happen if all
  # goes well, and add a handler at the end to capture errors, like you can
  # with synchronous code and exception handlers. You can also add steps that
  # recover from failures. See below, and the docs for {Combinators} for examples
  # on how to compose asynchronous operations.
  #
  # The mixins {Combinators}, {Callbacks} and {Factories} contain most of the
  # method you would use to work with futures, and can be used for creating bridges
  # to other futures implementations.
  #
  # @example Creating a future for a blocking operation
  #   def find_my_ip
  #     promise = Promse.new
  #     Thread.start do
  #       begin
  #         data = JSON.load(open('http://jsonip.org/').read)
  #         promise.fulfill(data['ip'])
  #       rescue => e
  #         promise.fail(e)
  #       end
  #     end
  #     promise.future
  #   end
  #
  # @example Transforming futures
  #   # find_my_ip is the method from the example above
  #   ip_future = find_my_ip
  #   # Future#map returns a new future that resolves to the value returned by the
  #   # block, but the block is not called immediately, but when the receiving
  #   # future resolves – this means that we can descrbe the processing steps that
  #   # should be performed without having to worry about when the value becomes
  #   # available.
  #   ipaddr_future = ip_future.map { |ip| IPAddr.new(ip) }
  #
  # @example Composing asynchronous operations
  #   # find_my_ip is the method from the example above
  #   ip_future = find_my_ip
  #   # Future#flat_map is a way of chaining asynchronous operations, the future
  #   # it returns will resolve to the value of the future returned by the block,
  #   # but the block is not called until the receiver future resolves
  #   location_future = ip_future.flat_map do |ip|
  #     # assuming resolve_geoip is a method returning a future
  #     resolve_geoip(ip)
  #   end
  #   # scheduler here could be an instance of Ione::Io::IoReactor
  #   timer_future = scheduler.schedule_timer(5)
  #   # Future.first returns a future that will resolve to the value of the
  #   # first of its children that completes, so you can use it in combination
  #   # with a scheduler to make sure you don't wait forever
  #   location_or_timeout_future = Future.first(location_future, timer_future)
  #   location_or_timeout_future.on_value do |location|
  #     if location
  #       puts "My location is #{location}"
  #     end
  #   end
  #
  # @example Making requests in parallel and collecting the results
  #   # assuming client is a client for a remote service and that #find returns
  #   # a future, and that thing_ids is an array of IDs of things we want to load
  #   futures = thing_idss.map { |id| client.find(id) }
  #   # Future.all is a way to combine multiple futures into a future that resolves
  #   # to an array of values, in other words, it takes an array of futures and
  #   # resolves to an array of the values of those futures
  #   future_of_all_things = Future.all(futures)
  #   future_of_all_things.on_value do |things|
  #     things.each do |thing|
  #       puts "here's a thing: #{thing}"
  #     end
  #   end
  #
  # @example Another way of making requests in parallel and collecting the results
  #   # the last example can be simplified by using Future.traverse, which combines
  #   # Array#map with Future.all – the block will be called once per item in
  #   # the array, and the returned future resolves to an array of the values of
  #   # the futures returned by the block
  #   future_of_all_things = Future.traverse(thing_ids) { |id| client.find(id) }
  #   future_of_all_things.on_value do |things|
  #     things.each do |thing|
  #       puts "here's a thing: #{thing}"
  #     end
  #   end
  #
  # @see Ione::Promise
  # @see Ione::Future::FutureCallbacks
  # @see Ione::Future::FutureCombinators
  # @see Ione::Future::FutureFactories
  # @since v1.0.0
  class Future
    # @since v1.0.0
    module Factories
      # Combines multiple futures into a new future which resolves when all
      # constituent futures complete, or fails when one or more of them fails.
      #
      # The value of the combined future is an array of the values of the
      # constituent futures.
      #
      # @example
      #   ids = [1, 2, 3, 4]
      #   futures = ids.map { |id| find_thing(id) }
      #   future = Future.all(ids)
      #   future.value # => [thing1, thing2, thing3, thing4]
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
      # @example Speculative execution
      #   # make a call to multiple services and use the value of the one that
      #   # responds first – and discard the other results
      #   f1 = service1.find_thing(id)
      #   f2 = service2.find_thing(id)
      #   f3 = service3.find_thing(id)
      #   f = Future.first(f1, f2, f3)
      #   f.value # => the value of the call that was quickest
      #
      # @param [Array<Ione::Future>] futures the futures to monitor (this argument
      #   can be a splatted array or a regular array passed as sole argument)
      # @return [Ione::Future] a future which represents the first completing future
      def first(*futures)
        if futures.size == 1 && (fs = futures.first).is_a?(Enumerable)
          futures = fs
        end
        if futures.count == 0
          resolved
        else
          FirstFuture.new(futures)
        end
      end

      # Takes calls the block once for each element in an array, expecting each
      # invocation to return a future, and returns a future that resolves to
      # an array of the values of those futures.
      #
      # @example
      #   ids = [1, 2, 3]
      #   future = Future.traverse(ids) { |id| find_thing(id) }
      #   future.value # => [thing1, thing2, thing3]
      #
      # @param [Array<Object>] values an array whose elements will be passed to
      #   the block, one by one
      # @yieldparam [Object] value each element from the array
      # @yieldreturn [Ione::Future] a future
      # @return [Ione::Future] a future that will resolve to an array of the values
      #   of the futures returned by the block
      # @since v1.2.0
      def traverse(values, &block)
        all(values.map(&block))
      rescue => e
        failed(e)
      end

      # Returns a future that will resolve to a value which is the reduction of
      # the values of a list of source futures.
      #
      # This is essentially a parallel, streaming version of `Enumerable#reduce`,
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
      #   merged_future.value # => the result of {}.merge(hash1).merge(hash2), etc.
      #
      # @example Reducing with an associative and commutative function, like addition
      #   futures = ... # a list of futures that will resolve to numbers
      #   sum_future = Future.reduce(futures, 0, ordered: false) do |accumulator, value|
      #     accumulator + value
      #   end
      #   sum_future.value # => the sum of all values
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
      # @since v1.2.0
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
        if value.nil?
          ResolvedFuture::NIL
        else
          ResolvedFuture.new(value)
        end
      end

      # Creates a new pre-failed future.
      #
      # @param [Error] error the error of the created future
      # @return [Ione::Future] a failed future
      def failed(error)
        FailedFuture.new(error)
      end
    end

    # @since v1.0.0
    module Combinators
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
        if resolved?
          begin
            Future.resolved(block ? block.call(@value) : value)
          rescue => e
            Future.failed(e)
          end
        elsif failed?
          self
        else
          f = CompletableFuture.new
          on_complete do |v, e|
            if e
              f.fail(e)
            elsif block.nil?
              f.resolve(value)
            else
              f.try(v, &block)
            end
          end
          f
        end
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
        if resolved?
          begin
            block.call(@value)
          rescue => e
            Future.failed(e)
          end
        elsif failed?
          self
        else
          f = CompletableFuture.new
          on_complete do
            f.observe(flat_map(&block))
          end
          f
        end
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
      # @since v1.2.0
      def then(&block)
        if resolved?
          begin
            fv = block.call(@value)
            if fv.respond_to?(:on_complete)
              fv
            else
              Future.resolved(fv)
            end
          rescue => e
            Future.failed(e)
          end
        elsif failed?
          self
        else
          f = CompletableFuture.new
          on_complete do
            f.observe(self.then(&block))
          end
          f
        end
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
        if resolved?
          self
        elsif failed?
          begin
            Future.resolved(block ? block.call(@error) : value)
          rescue => e
            Future.failed(e)
          end
        else
          f = CompletableFuture.new
          on_complete do
            f.observe(recover(value, &block))
          end
          f
        end
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
        if resolved?
          self
        elsif failed?
          begin
            block.call(@error)
          rescue => e
            Future.failed(e)
          end
        else
          f = CompletableFuture.new
          on_complete do
            f.observe(fallback(&block))
          end
          f
        end
      end
    end

    # @since v1.0.0
    module Callbacks
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

    extend Factories
    include Combinators
    include Callbacks

    # @private
    def initialize
      @lock = Mutex.new
      @state = :pending
      @listeners = []
    end

    # Registers a listener that will be called when this future completes,
    # i.e. resolves or fails. The listener will be called with the future as
    # solve argument.
    #
    # The order in which listeners are called is not defined and implementation
    # dependent. The thread the listener will be called on is also not defined
    # and implementation dependent. The default implementation calls listeners
    # registered before completion on the thread that completed the future, and
    # listeners registered after completions on the thread that registers the
    # listener – but this may change in the future, and may be different in
    # special circumstances.
    #
    # When a listener raises an error it will be swallowed and not re-raised.
    # The reason for this is that the processing of the callback may be done
    # in a context that does not expect, nor can recover from, errors. Not
    # swallowing errors would stop other listeners from being called. If it
    # appears as if a listener is not called, first make sure it is not raising
    # any errors (even a syntax error or a spelling mistake in a method or
    # variable name will not be hidden).
    #
    # @note
    #   Depending on the arity of the listener it will be passed different
    #   arguments. When the listener takes one argument it will receive the
    #   future itself as argument (this is backwards compatible with the pre
    #   v1.2 behaviour), with two arguments the value and error are given,
    #   with three arguments the value, error and the future itself will be
    #   given. The listener can also take no arguments. See the tests to find
    #   out the nitty-gritty details, for example the behaviour with different
    #   combinations of variable arguments and default values.
    #
    #   Most of the time you will use {#on_value} and {#on_failure}, and not
    #   instead of this method.
    #
    # @yieldparam [Object] value the value that the future resolves to
    # @yieldparam [Error] error the error that failed this future
    # @yieldparam [Ione::Future] future the future itself
    # @see Callbacks#on_value
    # @see Callbacks#on_failure
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
    # @note
    #   This is a blocking operation and should be used with caution. You should
    #   never call this method in a block given to any of the other methods
    #   on {Future}. Prefer using combinator methods like {#map} and {#flat_map}
    #   to compose operations asynchronously, or use {#on_value}, {#on_failure}
    #   or {#on_complete} to listen for values and/or failures.
    #
    # @raise [Error] the error that failed this future
    # @return [Object] the value of this future
    # @see Callbacks#on_value
    # @see Callbacks#on_failure
    # @see Callbacks#on_complete
    def value
      if @state == :failed
        raise @error
      elsif @state == :resolved
        @value
      else
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
    end
    alias_method :get, :value

    # Returns true if this future is resolved or failed
    def completed?
      if @state == :pending
        @lock.lock
        begin
          @state != :pending
        ensure
          @lock.unlock
        end
      else
        true
      end
    end

    # Returns true if this future is resolved
    def resolved?
      if @state == :pending
        @lock.lock
        begin
          @state == :resolved
        ensure
          @lock.unlock
        end
      else
        @state == :resolved
      end
    end

    # Returns true if this future has failed
    def failed?
      if @state == :pending
        @lock.lock
        begin
          @state == :failed
        ensure
          @lock.unlock
        end
      else
        @state == :failed
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
  # @deprecated
  FutureCallbacks = Future::Callbacks

  # @private
  # @deprecated
  FutureCombinators = Future::Combinators

  # @private
  # @deprecated
  FutureFactories = Future::Factories

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

    def observe(future)
      future.on_complete do |v, e|
        if e
          fail(e)
        else
          resolve(v)
        end
      end
    end

    def try(*ctx)
      resolve(yield(*ctx))
    rescue => e
      fail(e)
    end
  end

  # @private
  class CombinedFuture < CompletableFuture
    def initialize(futures)
      super()
      @index = 0
      @futures = Array(futures)
      @values = Array.new(@futures.size)
      await_next
    end

    private

    def await_next
      @futures[@index].on_complete do |v, e|
        if e
          fail(e)
          @futures = nil
          @values = nil
        else
          @values[@index] = v
          @index += 1
          if @index == @values.size
            resolve(@values)
            @futures = nil
            @values = nil
          else
            await_next
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
