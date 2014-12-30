# encoding: utf-8

require 'spec_helper'


module Ione
  class Stream
    describe Source do
      let :stream do
        described_class.new
      end

      describe '#<<' do
        it 'publishes an element to the stream' do
          published_elements = []
          stream.each { |e| published_elements << e }
          stream << 'foo'
          published_elements.should == ['foo']
        end

        it 'returns the message' do
          (stream << 'foo').should == 'foo'
        end

        it 'delivers the element to all listeners' do
          published_elements1 = []
          published_elements2 = []
          published_elements3 = []
          stream.each { |e| published_elements1 << e }
          stream.each { |e| published_elements2 << e }
          stream.each { |e| published_elements3 << e }
          stream << 'foo'
          published_elements1.should == ['foo']
          published_elements2.should == ['foo']
          published_elements3.should == ['foo']
        end

        it 'ignores errors raised by listeners' do
          published_elements1 = []
          published_elements2 = []
          stream.each { |e| raise 'bork!' }
          stream.each { |e| published_elements2 << e }
          stream << 'foo'
          published_elements1.should == []
          published_elements2.should == ['foo']
        end
      end

      describe '#subscribe' do
        context 'when given a block' do
          it 'yields each element that is pushed to the stream' do
            yielded_elements = []
            stream.subscribe { |e| yielded_elements << e }
            stream << 'foo'
            stream << 'bar'
            yielded_elements.should == ['foo', 'bar']
          end

          it 'returns the subscriber' do
            stream.subscribe { }.should be_a(Proc)
          end
        end

        context 'when given a subscriber' do
          let :subscriber do
            StreamSpec::Subscriber.new
          end

          it 'delivers each element that is pushed to the stream' do
            stream.subscribe(subscriber)
            stream << 'foo'
            stream << 'bar'
            subscriber.received_elements.should == ['foo', 'bar']
          end

          it 'returns the subscriber' do
            stream.subscribe(subscriber).should equal(subscriber)
          end
        end

        context 'when given a callable' do
          it 'delivers each element that is pushed to the stream' do
            delivered_elements = []
            stream.subscribe(proc { |e| delivered_elements << e })
            stream << 'foo'
            stream << 'bar'
            delivered_elements.should == ['foo', 'bar']
          end

          it 'returns the subscriber' do
            subscriber = proc { |e| delivered_elements << e }
            stream.subscribe(subscriber).should equal(subscriber)
          end
        end

        context 'when given something that does not respond to neither #receive nor #call' do
          it 'raises ArgumentError' do
            expect { stream.subscribe('foo') }.to raise_error(ArgumentError)
            expect { stream.subscribe }.to raise_error(ArgumentError)
          end
        end

        it 'is aliased as #each' do
          published_elements = []
          stream.each { |e| published_elements << e }
          stream << 'foo'
          stream << 'bar'
          published_elements.should == ['foo', 'bar']
        end
      end

      describe '#unsubscribe' do
        context 'with a Proc subscriber' do
          it 'stops delivering messages to the subscriber' do
            delivered_elements = []
            subscriber = proc { |e| delivered_elements << e }
            stream.subscribe(subscriber)
            stream << 'foo'
            stream << 'bar'
            stream.unsubscribe(subscriber)
            stream << 'baz'
            delivered_elements.should_not include('baz')
          end
        end

        context 'with a Subscriber subscriber' do
          it 'stops delivering messages to the subscriber' do
            subscriber = StreamSpec::Subscriber.new
            stream.subscribe(subscriber)
            stream << 'foo'
            stream << 'bar'
            stream.unsubscribe(subscriber)
            stream << 'baz'
            subscriber.received_elements.should_not include('baz')
          end
        end
      end

      describe '#map' do
        it 'returns a stream of elements transformed by the specified block' do
          published_elements = []
          transformed_stream = stream.map { |e| e.reverse }
          transformed_stream.each { |e| published_elements << e }
          stream << 'foo'
          stream << 'bar'
          published_elements.should == ['oof', 'rab']
        end
      end

      describe '#select' do
        it 'returns a stream of the elements for which the specified block returns true' do
          published_elements = []
          filtered_stream = stream.select { |e| e.include?('a') }
          filtered_stream.each { |e| published_elements << e }
          stream << 'foo'
          stream << 'bar'
          stream << 'baz'
          stream << 'qux'
          published_elements.should == ['bar', 'baz']
        end
      end

      describe '#aggregate' do
        it 'returns a stream of new elements produced by the specified block' do
          published_elements = []
          sum = 0
          aggregate_stream = stream.aggregate do |e, downstream|
            sum += e
            downstream << sum
          end
          aggregate_stream.each { |e| published_elements << e }
          1.upto(5) { |n| stream << n }
          published_elements.should == [1, 1 + 2, 1 + 2 + 3, 1 + 2 + 3 + 4, 1 + 2 + 3 + 4 + 5]
        end

        it 'passes the given argument to the first invocation of the block, and the block\'s return value on each subsequent invocation' do
          published_elements = []
          aggregate_stream = stream.aggregate('') do |e, downstream, buffer|
            buffer << e
            while (i = buffer.index("\n"))
              downstream << buffer.slice!(0, i + 1)
            end
            buffer
          end
          aggregate_stream.each { |e| published_elements << e }
          stream << "fo"
          stream << "o\nbar\nba"
          stream << "z\n"
          published_elements.should == ["foo\n", "bar\n", "baz\n"]
        end
      end

      describe '#take' do
        it 'returns a stream of only the specified number of elements' do
          published_elements = []
          filtered_stream = stream.take(3)
          filtered_stream.each { |e| published_elements << e }
          stream << 'foo'
          stream << 'bar'
          stream << 'baz'
          stream << 'qux'
          published_elements.should == ['foo', 'bar', 'baz']
        end
      end

      describe '#drop' do
        it 'returns a stream that will skip the specified number of items' do
          published_elements = []
          filtered_stream = stream.drop(2)
          filtered_stream.each { |e| published_elements << e }
          stream << 'foo'
          stream << 'bar'
          stream << 'baz'
          stream << 'qux'
          published_elements.should == ['baz', 'qux']
        end
      end
    end
  end
end

module StreamSpec
  class Subscriber
    include Ione::Stream::Subscriber

    attr_reader :received_elements

    def initialize
      @received_elements = []
    end

    def call(element)
      @received_elements << element
    end
  end
end