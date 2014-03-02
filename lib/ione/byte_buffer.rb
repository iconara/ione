# encoding: utf-8

module Ione
  # A byte buffer is a more efficient way of working with bytes than using
  # a regular Ruby string. It also has convenient methods for reading integers
  # shorts and single bytes that are faster than `String#unpack`.
  #
  # When you use a string as a buffer, by adding to the end and taking away
  # from the beginning, Ruby will continue to grow the backing array of
  # characters. This means that the longer you use the string the worse the
  # performance will get and the more memory you waste.
  #
  # {ByteBuffer} solves the problem by using two strings: one is the read
  # buffer and one is the write buffer. Writes go to the write buffer only,
  # and reads read from the read buffer until it is empty, then a new write
  # buffer is created and the old write buffer becomes the new read buffer.
  class ByteBuffer
    def initialize(initial_bytes='')
      @read_buffer = ''
      @write_buffer = ''
      @offset = 0
      @length = 0
      append(initial_bytes) unless initial_bytes.empty?
    end

    # Returns the number of bytes in the buffer.
    #
    # The value is cached so this is a cheap operation.
    attr_reader :length
    alias_method :size, :length
    alias_method :bytesize, :length

    # Returns true when the number of bytes in the buffer is zero.
    #
    # The length is cached so this is a cheap operation.
    def empty?
      length == 0
    end

    # Append the bytes from a string or another byte buffer to this buffer.
    #
    # @note
    #   When the bytes are not in an ASCII compatible encoding they are copied
    #   and retagged as `Encoding::BINARY` before they are appended to the
    #   buffer – this is required to avoid Ruby retagging the whole buffer with
    #   the encoding of the new bytes. If you can, make sure that the data you
    #   append is ASCII compatible (i.e. responds true to `#ascii_only?`),
    #   otherwise you will pay a small penalty for each append due to the extra
    #   copy that has to be made.
    #
    # @param [String, Ione::ByteBuffer] bytes the bytes to append
    # @return [Ione::ByteBuffer] itself
    def append(bytes)
      if bytes.is_a?(self.class)
        bytes.append_to(self)
      else
        bytes = bytes.to_s
        unless bytes.ascii_only?
          bytes = bytes.dup.force_encoding(::Encoding::BINARY)
        end
        retag = @write_buffer.empty?
        @write_buffer << bytes
        @write_buffer.force_encoding(::Encoding::BINARY) if retag
        @length += bytes.bytesize
      end
      self
    end
    alias_method :<<, :append

    # Remove the first N bytes from the buffer.
    #
    # @param [Integer] n the number of bytes to remove from the buffer
    # @return [Ione::ByteBuffer] itself
    # @raise RangeError when there are not enough bytes in the buffer
    def discard(n)
      raise RangeError, 'Cannot discard a negative number of bytes' if n < 0
      raise RangeError, "#{n} bytes to discard but only #{@length} available" if @length < n
      @offset += n
      @length -= n
      self
    end

    # Remove and return the first N bytes from the buffer.
    #
    # @param [Integer] n the number of bytes to remove and return from the buffer
    # @return [String] a string with the bytes, the string will be tagged
    #   with `Encoding::BINARY`.
    # @raise RangeError when there are not enough bytes in the buffer
    def read(n)
      raise RangeError, 'Cannot read a negative number of bytes' if n < 0
      raise RangeError, "#{n} bytes required but only #{@length} available" if @length < n
      if @offset >= @read_buffer.bytesize
        swap_buffers
      end
      if @offset + n > @read_buffer.bytesize
        s = read(@read_buffer.bytesize - @offset)
        s << read(n - s.bytesize)
        s
      else
        s = @read_buffer[@offset, n]
        @offset += n
        @length -= n
        s
      end
    end

    # Remove and return the first four bytes from the buffer and decode them as an unsigned integer.
    #
    # @return [Integer] the big-endian integer interpretation of the four bytes
    # @raise RangeError when there are not enough bytes in the buffer
    def read_int
      raise RangeError, "4 bytes required to read an int, but only #{@length} available" if @length < 4
      if @offset >= @read_buffer.bytesize
        swap_buffers
      end
      if @read_buffer.bytesize >= @offset + 4
        i0 = @read_buffer.getbyte(@offset + 0)
        i1 = @read_buffer.getbyte(@offset + 1)
        i2 = @read_buffer.getbyte(@offset + 2)
        i3 = @read_buffer.getbyte(@offset + 3)
        @offset += 4
        @length -= 4
      else
        i0 = read_byte
        i1 = read_byte
        i2 = read_byte
        i3 = read_byte
      end
      (i0 << 24) | (i1 << 16) | (i2 << 8) | i3
    end

    # Remove and return the first two bytes from the buffer and decode them as an unsigned integer.
    #
    # @return [Integer] the big-endian integer interpretation of the two bytes
    # @raise RangeError when there are not enough bytes in the buffer
    def read_short
      raise RangeError, "2 bytes required to read a short, but only #{@length} available" if @length < 2
      if @offset >= @read_buffer.bytesize
        swap_buffers
      end
      if @read_buffer.bytesize >= @offset + 2
        i0 = @read_buffer.getbyte(@offset + 0)
        i1 = @read_buffer.getbyte(@offset + 1)
        @offset += 2
        @length -= 2
      else
        i0 = read_byte
        i1 = read_byte
      end
      (i0 << 8) | i1
    end

    # Remove and return the first byte from the buffer and decode it as a signed or unsigned integer.
    #
    # @param [Boolean] signed whether or not to interpret the byte as a signed number of not
    # @return [Integer] the integer interpretation of the byte
    # @raise RangeError when the buffer is empty
    def read_byte(signed=false)
      raise RangeError, "No bytes available to read byte" if empty?
      if @offset >= @read_buffer.bytesize
        swap_buffers
      end
      b = @read_buffer.getbyte(@offset)
      b = (b & 0x7f) - (b & 0x80) if signed
      @offset += 1
      @length -= 1
      b
    end

    def index(substring, start_index=0)
      if @offset >= @read_buffer.bytesize
        swap_buffers
      end
      read_buffer_length = @read_buffer.bytesize
      if start_index < read_buffer_length - @offset && (index = @read_buffer.index(substring, @offset + start_index))
        index - @offset
      elsif (index = @write_buffer.index(substring, start_index - read_buffer_length + @offset))
        index + read_buffer_length - @offset
      else
        nil
      end
    end

    # Overwrite a portion of the buffer with new bytes.
    #
    # The number of bytes that will be replaced depend on the size of the
    # replacement string. If you pass a five byte string the five bytes
    # starting at the location will be replaced.
    #
    # When you pass more bytes than the size of the buffer after the location
    # only as many as needed to replace the remaining bytes of the buffer will
    # actually be used.
    #
    # Make sure that you get your location right, if you have discarded bytes
    # from the buffer all of the offsets will have changed.
    #
    # @example replacing bytes in the middle of a buffer
    #   buffer = ByteBuffer.new("hello world!")
    #   bufferupdate(6, "fnord")
    #   buffer # => "hello fnord!"
    #
    # @example replacing bytes at the end of the buffer
    #   buffer = ByteBuffer.new("my name is Jim")
    #   buffer.update(11, "Sammy")
    #   buffer # => "my name is Sam"
    #
    # @param [Integer] location the starting location where the new bytes
    #   should be inserted
    # @param [String] bytes the replacement bytes
    # @return [Ione::ByteBuffer] itself
    def update(location, bytes)
      absolute_offset = @offset + location
      bytes_length = bytes.bytesize
      if absolute_offset >= @read_buffer.bytesize
        @write_buffer[absolute_offset - @read_buffer.bytesize, bytes_length] = bytes
      else
        overflow = absolute_offset + bytes_length - @read_buffer.bytesize
        read_buffer_portion = bytes_length - overflow
        @read_buffer[absolute_offset, read_buffer_portion] = bytes[0, read_buffer_portion]
        if overflow > 0
          @write_buffer[0, overflow] = bytes[read_buffer_portion, bytes_length - 1]
        end
      end
      self
    end

    # Return as much of the buffer as possible without having to concatenate
    # or allocate any unnecessary strings.
    #
    # If the buffer is not empty this method will return something, but there
    # are no guarantees as to how much it will return. It's primarily useful
    # in situations where a loop wants to offer some bytes but can't be sure
    # how many will be accepted — for example when writing to a socket.
    #
    # @example feeding bytes to a socket
    #   while true
    #     _, writables, _ = IO.select(nil, sockets)
    #     if writables
    #       writables.each do |io|
    #         n = io.write_nonblock(buffer.cheap_peek)
    #         buffer.discard(n)
    #       end
    #     end
    #
    # @return [String] some bytes from the start of the buffer
    def cheap_peek
      if @offset >= @read_buffer.bytesize
        swap_buffers
      end
      @read_buffer[@offset, @read_buffer.bytesize - @offset]
    end

    def eql?(other)
      self.to_str.eql?(other.to_str)
    end
    alias_method :==, :eql?

    def hash
      to_str.hash
    end

    def dup
      self.class.new(to_str)
    end

    def to_str
      (@read_buffer + @write_buffer)[@offset, @length]
    end
    alias_method :to_s, :to_str

    def inspect
      %(#<#{self.class.name}: #{to_str.inspect}>)
    end

    protected

    def append_to(other)
      other.raw_append(cheap_peek)
      other.raw_append(@write_buffer) unless @write_buffer.empty?
    end

    def raw_append(bytes)
      @write_buffer << bytes
      @length += bytes.bytesize
    end

    private

    def swap_buffers
      @offset -= @read_buffer.bytesize
      @read_buffer = @write_buffer
      @write_buffer = ''
    end
  end
end