# encoding: utf-8

require 'spec_helper'


module Ione
  class Stream
    describe PushStream do
      let :stream do
        described_class.new
      end

      describe '#push' do
        it 'pushes an element to the stream' do
          pushed_elements = []
          stream.each { |e| pushed_elements << e }
          stream.push('foo')
          pushed_elements.should == ['foo']
        end

        it 'is aliased as #<<' do
          pushed_elements = []
          stream.each { |e| pushed_elements << e }
          stream << 'foo'
          pushed_elements.should == ['foo']
        end

        it 'returns self' do
          stream.push('foo').should equal(stream)
        end

        it 'delivers the element to all listeners' do
          pushed_elements1 = []
          pushed_elements2 = []
          pushed_elements3 = []
          stream.each { |e| pushed_elements1 << e }
          stream.each { |e| pushed_elements2 << e }
          stream.each { |e| pushed_elements3 << e }
          stream.push('foo')
          pushed_elements1.should == ['foo']
          pushed_elements2.should == ['foo']
          pushed_elements3.should == ['foo']
        end

        it 'ignores errors raised by listeners' do
          pushed_elements1 = []
          pushed_elements2 = []
          stream.each { |e| raise 'bork!' }
          stream.each { |e| pushed_elements2 << e }
          stream.push('foo')
          pushed_elements1.should == []
          pushed_elements2.should == ['foo']
        end
      end

      describe '#subscribe' do
        it 'yields each element that is pushed to the stream' do
          pushed_elements = []
          stream.subscribe { |e| pushed_elements << e }
          stream.push('foo')
          stream.push('bar')
          pushed_elements.should == ['foo', 'bar']
        end

        it 'returns self' do
          stream.subscribe { }.should equal(stream)
        end

        it 'is aliased as #each' do
          pushed_elements = []
          stream.each { |e| pushed_elements << e }
          stream.push('foo')
          stream.push('bar')
          pushed_elements.should == ['foo', 'bar']
        end
      end

      describe '#to_proc' do
        it 'returns a Proc that can be used to push elements to the stream' do
          pushed_elements = []
          another_stream = described_class.new
          another_stream.each { |e| pushed_elements << e}
          stream.each(&another_stream)
          stream << 'foo'
          stream << 'bar'
          pushed_elements.should == ['foo', 'bar']
        end
      end

      describe '#map' do
        it 'returns a stream of elements transformed by the specified block' do
          pushed_elements = []
          transformed_stream = stream.map { |e| e.reverse }
          transformed_stream.each { |e| pushed_elements << e }
          stream << 'foo'
          stream << 'bar'
          pushed_elements.should == ['oof', 'rab']
        end
      end

      describe '#select' do
        it 'returns a stream of the elements for which the specified block returns true' do
          pushed_elements = []
          filtered_stream = stream.select { |e| e.include?('a') }
          filtered_stream.each { |e| pushed_elements << e }
          stream << 'foo'
          stream << 'bar'
          stream << 'baz'
          stream << 'qux'
          pushed_elements.should == ['bar', 'baz']
        end
      end

      describe '#aggregate' do
        it 'returns a stream of new elements produced by the specified block' do
          pushed_elements = []
          sum = 0
          aggregate_stream = stream.aggregate do |e, downstream|
            sum += e
            downstream << sum
          end
          aggregate_stream.each { |e| pushed_elements << e }
          1.upto(5) { |n| stream.push(n) }
          pushed_elements.should == [1, 1 + 2, 1 + 2 + 3, 1 + 2 + 3 + 4, 1 + 2 + 3 + 4 + 5]
        end

        it 'passes the given argument to the first invocation of the block, and the block\'s return value on each subsequent invocation' do
          pushed_elements = []
          aggregate_stream = stream.aggregate('') do |e, downstream, buffer|
            buffer << e
            while (i = buffer.index("\n"))
              downstream << buffer.slice!(0, i + 1)
            end
            buffer
          end
          aggregate_stream.each { |e| pushed_elements << e }
          stream << "fo"
          stream << "o\nbar\nba"
          stream << "z\n"
          pushed_elements.should == ["foo\n", "bar\n", "baz\n"]
        end
      end

      describe '#take' do
        it 'returns a stream of only the specified number of elements' do
          pushed_elements = []
          filtered_stream = stream.take(3)
          filtered_stream.each { |e| pushed_elements << e }
          stream << 'foo'
          stream << 'bar'
          stream << 'baz'
          stream << 'qux'
          pushed_elements.should == ['foo', 'bar', 'baz']
        end
      end

      describe '#drop' do
        it 'returns a stream that will skip the specified number of items' do
          pushed_elements = []
          filtered_stream = stream.drop(2)
          filtered_stream.each { |e| pushed_elements << e }
          stream << 'foo'
          stream << 'bar'
          stream << 'baz'
          stream << 'qux'
          pushed_elements.should == ['baz', 'qux']
        end
      end
    end
  end
end
