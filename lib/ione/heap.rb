# encoding: utf-8

module Ione
  # @private
  class Heap
    def initialize
      @items = []
    end

    def size
      @items.size
    end

    def empty?
      @items.empty?
    end

    def push(item)
      @items << item
      bubble_up(@items.size - 1)
    end
    alias_method :<<, :push

    def peek
      @items.first
    end

    def pop
      if @items.size == 0
        nil
      elsif @items.size == 1
        @items.pop
      else
        item = @items.first
        @items[0] = @items.pop
        bubble_down(0)
        item
      end
    end

    def delete(item)
      if item == @items.first
        pop
      elsif item == @items.last
        @items.pop
      elsif (i = index(item))
        item = @items[i]
        @items[i] = @items.pop
        bubble_up(bubble_down(i))
        item
      end
    end

    private

    def index(item, root_index=0)
      left_index = (root_index * 2) + 1
      right_index = (root_index * 2) + 2
      root_item = @items[root_index]
      if root_item == item
        root_index
      elsif left_index < @items.length && item >= @items[left_index] && (i = index(item, left_index))
        i
      elsif right_index < @items.length && item >= @items[right_index] && (i = index(item, right_index))
        i
      end
    end

    def bubble_up(index)
      parent_index = (index - 1)/2
      if parent_index >= 0 && @items[parent_index] > @items[index]
        item = @items[index]
        @items[index] = @items[parent_index]
        @items[parent_index] = item
        bubble_up(parent_index)
      else
        index
      end
    end

    def bubble_down(index)
      child_index = (index * 2) + 1
      if child_index >= @items.length
        index
      else
        if child_index + 1 < @items.length && @items[child_index] > @items[child_index + 1]
          child_index += 1
        end
        if @items[index] > @items[child_index]
          item = @items[index]
          @items[index] = @items[child_index]
          @items[child_index] = item
          bubble_down(child_index)
        else
          index
        end
      end
    end
  end
end
