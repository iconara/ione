# encoding: utf-8

module Ione
  # @private
  class Heap
    def initialize
      @items = []
      @indexes = {}
    end

    def size
      @items.size
    end

    def empty?
      @items.empty?
    end

    def push(item)
      unless @indexes.include?(item)
        @items << item
        @indexes[item] = @items.size - 1
        bubble_up(@items.size - 1)
      end
    end
    alias_method :<<, :push

    def peek
      @items.first
    end

    def pop
      if @items.size == 0
        nil
      elsif @items.size == 1
        item = @items.pop
        @indexes.delete(item)
        item
      else
        item = @items.first
        @indexes.delete(item)
        @items[0] = @items.pop
        @indexes[@items[0]] = 0
        bubble_down(0)
        item
      end
    end

    def delete(item)
      if item == @items.first
        pop
      elsif item == @items.last
        item = @items.pop
        @indexes.delete(item)
        item
      elsif (i = @indexes[item])
        item = @items[i]
        @indexes.delete(item)
        @items[i] = @items.pop
        @indexes[@items[i]] = i
        bubble_up(bubble_down(i))
        item
      end
    end

    private

    def bubble_up(index)
      parent_index = (index - 1)/2
      if parent_index >= 0 && @items[parent_index] > @items[index]
        item = @items[index]
        @items[index] = @items[parent_index]
        @items[parent_index] = item
        @indexes[@items[index]] = index
        @indexes[@items[parent_index]] = parent_index
        bubble_up(parent_index)
      else
        index
      end
    end

    def bubble_down(index)
      child_index = (index * 2) + 1
      if child_index >= @items.size
        index
      else
        if child_index + 1 < @items.size && @items[child_index] > @items[child_index + 1]
          child_index += 1
        end
        if @items[index] > @items[child_index]
          item = @items[index]
          @items[index] = @items[child_index]
          @items[child_index] = item
          @indexes[@items[index]] = index
          @indexes[@items[child_index]] = child_index
          bubble_down(child_index)
        else
          index
        end
      end
    end
  end
end
