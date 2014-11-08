# encoding: utf-8

module Ione
  # @abstract Base class for streams
  # @see Ione::Stream::PushStream
  class Stream
    # @private
    def initialize
      @listeners = []
      @lock = Mutex.new
    end

    # @yieldparam [Object] element each element that flows through the stream
    # @return [self] the stream itself
    def each(&listener)
      @lock.lock
      listeners = @listeners.dup
      listeners << listener
      @listeners = listeners
      self
    ensure
      @lock.unlock
    end

    private

    def deliver(element)
      @listeners.each do |listener|
        listener.call(element) rescue nil
      end
      self
    end

    module StreamCombinators
      # @return [Ione::Stream]
      def map(&transformer)
        TransformedStream.new(self, transformer)
      end

      # @return [Ione::Stream]
      def select(&filter)
        FilteredStream.new(self, filter)
      end

      # @return [Ione::Stream]
      def aggregate(state=nil, &aggregator)
        AggregatingStream.new(self, aggregator, state)
      end
    end

    include StreamCombinators

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
  end
end
