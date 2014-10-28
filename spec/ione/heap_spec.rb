# encoding: utf-8

require 'spec_helper'


module Ione
  describe Heap do
    let :heap do
      described_class.new
    end

    describe '#size' do
      it 'is zero when the heap is empty' do
        heap.size.should be_zero
      end

      it 'returns the number of items in the heap' do
        heap.push(13)
        heap.push(100)
        heap.size.should == 2
        heap.push(101)
        heap.size.should == 3
      end
    end

    describe '#empty?' do
      it 'returns true when there are no items in the heap' do
        heap.should be_empty
      end

      it 'returns false when there are items in the heap' do
        heap.push(1)
        heap.should_not be_empty
      end
    end

    describe '#push' do
      it 'adds items to the heap' do
        heap.push(4)
        heap.push(3)
        heap.push(6)
        heap.push(5)
        heap.size.should == 4
      end

      it 'is aliased as #<<' do
        heap << 4
        heap << 3
        heap << 6
        heap << 5
        heap.size.should == 4
      end
    end

    describe '#peek' do
      it 'returns nil when there are no items in the heap' do
        heap.peek.should be_nil
      end

      it 'returns the only item when there is only one' do
        heap.push(3)
        heap.peek.should == 3
      end

      it 'returns the smallest item' do
        heap.push(10)
        heap.push(3)
        heap.push(7)
        heap.peek.should == 3
      end

      it 'does not remove the item from the heap' do
        heap.push(3)
        heap.peek.should == 3
        heap.peek.should == 3
        heap.peek.should == 3
      end
    end

    describe '#pop' do
      it 'returns nil when there are no items in the heap' do
        heap.pop.should be_nil
      end

      it 'returns and removes the only item when there is only one' do
        heap.push(3)
        heap.pop.should == 3
        heap.should be_empty
      end

      it 'returns and removes the smallest item' do
        heap.push(10)
        heap.push(3)
        heap.push(7)
        heap.pop.should == 3
        heap.pop.should == 7
        heap.size.should == 1
      end

      it 'removes the item from the heap' do
        heap.push(3)
        heap.pop.should == 3
        heap.pop.should be_nil
      end

      it 'returns each duplicate' do
        heap.push(3)
        heap.push(4)
        heap.push(3)
        heap.push(3)
        heap.pop.should == 3
        heap.pop.should == 3
        heap.pop.should == 3
        heap.pop.should == 4
      end
    end

    describe '#delete' do
      it 'removes the item from a heap with one item' do
        heap.push(3)
        heap.delete(3)
        heap.should be_empty
      end

      it 'removes the item from the heap' do
        heap.push(4)
        heap.push(3)
        heap.push(100)
        heap.push(101)
        heap.delete(4)
        heap.pop
        heap.peek.should == 100
        heap.size.should == 2
      end

      it 'removes the last item from the heap' do
        heap.push(1)
        heap.push(2)
        heap.push(3)
        heap.delete(3).should_not be_nil
        heap.delete(3).should be_nil
        heap.delete(2).should_not be_nil
        heap.delete(2).should be_nil
      end

      it 'correctly re-heapifies the heap after a delete' do
        heap.push(2)
        heap.push(6)
        heap.push(7)
        heap.push(8)
        heap.push(9)
        heap.push(3)
        heap.push(4)
        heap.delete(8).should_not be_nil
        heap.delete(4).should_not be_nil
      end

      it 'returns the item' do
        heap.push(3)
        heap.push(4)
        heap.push(5)
        heap.delete(4).should == 4
      end

      it 'returns nil when the item is not found' do
        heap.push(3)
        heap.push(4)
        heap.push(5)
        heap.delete(6).should be_nil
      end

      it 'removes the first instance of the item from the heap' do
        heap.push(3)
        heap.push(3)
        heap.push(5)
        heap.delete(3).should == 3
        heap.delete(3).should == 3
        heap.size.should == 1
      end
    end
  end
end
