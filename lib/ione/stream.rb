# encoding: utf-8

module Ione
  # @abstract Base class for streams
  # @see Ione::Stream::Publisher
  class Stream
    class Publisher
      # @private
      def initialize
        @subscribers = {}
        @lock = Mutex.new
      end

      # @yieldparam [Object] element each element that flows through the stream
      # @return [self] the stream itself
      def subscribe(subscriber=nil, &block)
        subscriber ||= block
        unless subscriber.respond_to?(:call)
          raise ArgumentError, %(A subscriber must respond to #call)
        end
        @lock.lock
        begin
          @subscribers[subscriber] = 1
          self
        ensure
          @lock.unlock
        end
        subscriber
      end
      alias_method :each, :subscribe

      # @param [Object] subscriber
      # @return [self] the stream itself
      def unsubscribe(subscriber)
        @lock.lock
        @subscribers.delete(subscriber)
        subscriber
      ensure
        @lock.unlock
      end
    end

    module Subscriber
      def call(element)
      end
    end

    module Combinators
      # @yieldparam [Object] element
      # @yieldreturn [Object] the transformed element
      # @return [Ione::Stream]
      def map(&transformer)
        subscribe(TransformedStream.new(transformer))
      end

      # @yieldparam [Object] element
      # @yieldreturn [Boolean] whether or not to pass the element downstream
      # @return [Ione::Stream]
      def select(&filter)
        subscribe(FilteredStream.new(filter))
      end

      # @param [Object] state
      # @yieldparam [Object] element
      # @yieldparam [Ione::Stream::Publisher] downstream
      # @yieldparam [Object] state
      # @yieldreturn [Object] the next state
      # @return [Ione::Stream]
      def aggregate(state=nil, &aggregator)
        subscribe(AggregatingStream.new(aggregator, state))
      end

      # @param [Integer] n the number of elements to pass downstream before
      #   unsubscribing
      # @return [Ione::Stream]
      def take(n)
        subscribe(LimitedStream.new(self, n))
      end

      # @param [Integer] n the number of elements to skip before passing
      #   elements downstream
      # @return [Ione::Stream]
      def drop(n)
        subscribe(SkippingStream.new(n))
      end
    end

    class Processor < Publisher
      include Subscriber
      include Combinators
    end

    class Source < Processor
      def <<(element)
        @subscribers.each_key do |subscriber|
          subscriber.call(element) rescue nil
        end
        element
      end
    end

    # @private
    class TransformedStream < Source
      def initialize(transformer)
        super()
        @transformer = transformer
      end

      def call(element)
        self << @transformer.call(element)
      end
    end

    # @private
    class FilteredStream < Source
      def initialize(filter)
        super()
        @filter = filter
      end

      def call(element)
        self << element if @filter.call(element)
      end
    end

    # @private
    class AggregatingStream < Source
      def initialize(aggregator, state)
        super()
        @aggregator = aggregator
        @state = state
      end

      def call(element)
        @state = @aggregator.call(element, self, @state)
      end
    end

    # @private
    class LimitedStream < Source
      def initialize(upstream, n)
        super()
        @upstream = upstream
        @counter = 0
        @limit = n
      end

      def call(element)
        if @counter < @limit
          self << element
        else
          @upstream.unsubscribe(self)
        end
        @counter += 1
      end
    end

    # @private
    class SkippingStream < Source
      def initialize(n)
        super()
        @counter = 0
        @skips = n
      end

      def call(element)
        if @counter == @skips
          self << element
        else
          @counter += 1
        end
      end
    end
  end
end
