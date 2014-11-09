# encoding: utf-8

module Ione
  # @abstract Base class for streams
  # @see Ione::Stream::PushStream
  class Stream
    # @private
    def initialize
      @subscribers = []
      @lock = Mutex.new
    end

    # @yieldparam [Object] element each element that flows through the stream
    # @return [self] the stream itself
    def subscribe(subscriber=nil, &block)
      @lock.lock
      subscribers = @subscribers.dup
      subscribers << (subscriber || block)
      @subscribers = subscribers
      self
    ensure
      @lock.unlock
    end
    alias_method :each, :subscribe

    def unsubscribe(subscriber)
      @lock.lock
      subscribers = @subscribers.dup
      subscribers.delete(subscriber)
      @subscribers = subscribers
    ensure
      @lock.unlock
    end

    private

    def deliver(element)
      @subscribers.each do |subscriber|
        subscriber.call(element) rescue nil
      end
      self
    end

    module Combinators
      # @yieldparam [Object] element
      # @yieldreturn [Object] the transformed element
      # @return [Ione::Stream]
      def map(&transformer)
        TransformedStream.new(self, transformer)
      end

      # @yieldparam [Object] element
      # @yieldreturn [Boolean] whether or not to pass the element downstream
      # @return [Ione::Stream]
      def select(&filter)
        FilteredStream.new(self, filter)
      end

      # @param [Object] state
      # @yieldparam [Object] element
      # @yieldparam [Ione::Stream::PushStream] downstream
      # @yieldparam [Object] state
      # @yieldreturn [Object] the next state
      # @return [Ione::Stream]
      def aggregate(state=nil, &aggregator)
        AggregatingStream.new(self, aggregator, state)
      end

      # @param [Integer] n the number of elements to pass downstream before
      #   unsubscribing
      # @return [Ione::Stream]
      def take(n)
        LimitedStream.new(self, n)
      end

      # @param [Integer] n the number of elements to skip before passing
      #   elements downstream
      # @return [Ione::Stream]
      def drop(n)
        SkippingStream.new(self, n)
      end
    end

    include Combinators

    class PushStream < Stream
      module_eval do
        # this crazyness is just to hide these declarations from Yard
        alias_method :push, :deliver
        public :push
        alias_method :<<, :deliver
        public :<<
      end

      # @!parse
      #   # @param [Object] element
      #   # @return [self]
      #   def push(element); end
      #   alias_method :<<, :push

      # @return [Proc] a Proc that can be used to push elements to this stream
      def to_proc
        method(:push).to_proc
      end
    end

    # @private
    class TransformedStream < Stream
      def initialize(upstream, transformer)
        super()
        upstream.each { |e| deliver(transformer.call(e)) }
      end
    end

    # @private
    class FilteredStream < Stream
      def initialize(upstream, filter)
        super()
        upstream.each { |e| deliver(e) if filter.call(e) }
      end
    end

    # @private
    class AggregatingStream < PushStream
      def initialize(upstream, aggregator, state)
        super()
        upstream.each { |e| state = aggregator.call(e, self, state) }
      end
    end

    # @private
    class LimitedStream < Stream
      def initialize(upstream, n)
        super()
        counter = 0
        subscriber = proc do |e|
          if counter < n
            deliver(e)
          else
            upstream.unsubscribe(subscriber)
          end
          counter += 1
        end
        upstream.subscribe(subscriber)
      end
    end

    # @private
    class SkippingStream < Stream
      def initialize(upstream, n)
        super()
        counter = 0
        upstream.subscribe do |e|
          if counter == n
            deliver(e)
          else
            counter += 1
          end
        end
      end
    end
  end
end
