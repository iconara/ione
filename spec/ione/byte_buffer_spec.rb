# encoding: utf-8

require 'spec_helper'


module Ione
  describe ByteBuffer do
    let :buffer do
      described_class.new
    end

    describe '#initialize' do
      it 'can be inititialized empty' do
        described_class.new.should be_empty
      end

      it 'can be initialized with bytes' do
        described_class.new('hello').length.should eq(5)
      end
    end

    describe '#length/#size/#bytesize' do
      it 'returns the number of bytes in the buffer' do
        buffer << 'foo'
        buffer.length.should eq(3)
      end

      it 'is zero initially' do
        buffer.length.should eq(0)
      end

      it 'is aliased as #size' do
        buffer << 'foo'
        buffer.size.should eq(3)
      end

      it 'is aliased as #bytesize' do
        buffer << 'foo'
        buffer.bytesize.should eq(3)
      end
    end

    describe '#empty?' do
      it 'is true initially' do
        buffer.should be_empty
      end

      it 'is false when there are bytes in the buffer' do
        buffer << 'foo'
        buffer.should_not be_empty
      end
    end

    describe '#append/#<<' do
      it 'adds bytes to the buffer' do
        buffer.append('foo')
        buffer.should_not be_empty
      end

      it 'can be used as <<' do
        buffer << 'foo'
        buffer.should_not be_empty
      end

      it 'returns itself' do
        buffer.append('foo').should eql(buffer)
      end

      it 'stores its bytes as binary' do
        buffer.append('hällö').length.should eq(7)
        buffer.to_s.encoding.should eq(::Encoding::BINARY)
      end

      it 'handles appending with multibyte strings' do
        buffer.append('hello')
        buffer.append('würld')
        buffer.to_s.should eq(String.new('hellowürld', encoding: ::Encoding::BINARY))
      end

      it 'handles appending with another byte buffer' do
        buffer.append('hello ').append(ByteBuffer.new('world'))
        buffer.to_s.should eq('hello world')
      end
    end

    describe '#eql?' do
      it 'is equal to another buffer with the same contents' do
        b1 = described_class.new
        b2 = described_class.new
        b1.append('foo')
        b2.append('foo')
        b1.should eql(b2)
      end

      it 'is not equal to another buffer with other contents' do
        b1 = described_class.new
        b2 = described_class.new
        b1.append('foo')
        b2.append('bar')
        b1.should_not eql(b2)
      end

      it 'is aliased as #==' do
        b1 = described_class.new
        b2 = described_class.new
        b1.append('foo')
        b2.append('foo')
        b1.should eq(b2)
      end

      it 'is equal to another buffer when both are empty' do
        b1 = described_class.new
        b2 = described_class.new
        b1.should eql(b2)
      end
    end

    describe '#hash' do
      it 'has the same hash code as another buffer with the same contents' do
        b1 = described_class.new
        b2 = described_class.new
        b1.append('foo')
        b2.append('foo')
        b1.hash.should eq(b2.hash)
      end

      it 'is not equal to the hash code of another buffer with other contents' do
        b1 = described_class.new
        b2 = described_class.new
        b1.append('foo')
        b2.append('bar')
        b1.hash.should_not == b2.hash
      end

      it 'is equal to the hash code of another buffer when both are empty' do
        b1 = described_class.new
        b2 = described_class.new
        b1.hash.should eq(b2.hash)
      end
    end

    describe '#to_s' do
      it 'returns the bytes' do
        buffer.append('hello world').to_s.should eq('hello world')
      end
    end

    describe '#to_str' do
      it 'returns the bytes' do
        buffer.append('hello world').to_str.should eq('hello world')
      end
    end

    describe '#inspect' do
      it 'returns the bytes wrapped in ByteBuffer(...)' do
        buffer.append("\xca\xfe")
        buffer.inspect.should eq('#<Ione::ByteBuffer: "\xCA\xFE">')
      end
    end

    describe '#discard' do
      it 'discards the specified number of bytes from the front of the buffer' do
        buffer.append('hello world')
        buffer.discard(4)
        buffer.should eq(ByteBuffer.new('o world'))
      end

      it 'returns the byte buffer' do
        buffer.append('hello world')
        buffer.discard(4).should eq(ByteBuffer.new('o world'))
      end

      it 'raises an error if the number of bytes in the buffer is fewer than the number to discard' do
        expect { buffer.discard(1) }.to raise_error(RangeError)
        buffer.append('hello')
        expect { buffer.discard(7) }.to raise_error(RangeError)
      end

      it 'raises an error when the specified number of bytes is negative' do
        buffer.append('hello')
        expect { buffer.discard(-7) }.to raise_error(RangeError)
      end
    end

    describe '#read' do
      it 'returns the specified number of bytes, as a string' do
        buffer.append('hello')
        buffer.read(4).should eq('hell')
      end

      it 'removes the bytes from the buffer' do
        buffer.append('hello')
        buffer.read(3)
        buffer.should eq(ByteBuffer.new('lo'))
        buffer.read(2).should eq('lo')
      end

      it 'raises an error if there are not enough bytes' do
        buffer.append('hello')
        expect { buffer.read(23423543) }.to raise_error(RangeError)
        expect { buffer.discard(5).read(1) }.to raise_error(RangeError)
      end

      it 'raises an error when the specified number of bytes is negative' do
        buffer.append('hello')
        expect { buffer.read(-4) }.to raise_error(RangeError)
      end

      it 'returns a string with binary encoding' do
        buffer.append('hello')
        buffer.read(4).encoding.should eq(::Encoding::BINARY)
        buffer.append('∆')
        buffer.read(2).encoding.should eq(::Encoding::BINARY)
      end
    end

    describe '#read_int' do
      it 'returns the first four bytes interpreted as an int' do
        buffer.append("\xca\xfe\xba\xbe\x01")
        buffer.read_int.should eq(0xcafebabe)
      end

      it 'removes the bytes from the buffer' do
        buffer.append("\xca\xfe\xba\xbe\x01")
        buffer.read_int
        buffer.should eq(ByteBuffer.new("\x01"))
      end

      it 'raises an error if there are not enough bytes' do
        buffer.append("\xca\xfe\xba")
        expect { buffer.read_int }.to raise_error(RangeError)
      end
    end

    describe '#read_short' do
      it 'returns the first two bytes interpreted as a short' do
        buffer.append("\xca\xfe\x01")
        buffer.read_short.should eq(0xcafe)
      end

      it 'removes the bytes from the buffer' do
        buffer.append("\xca\xfe\x01")
        buffer.read_short
        buffer.should eq(ByteBuffer.new("\x01"))
      end

      it 'raises an error if there are not enough bytes' do
        buffer.append("\xca")
        expect { buffer.read_short }.to raise_error(RangeError)
      end
    end

    describe '#read_byte' do
      it 'returns the first bytes interpreted as an int' do
        buffer.append("\x10\x01")
        buffer.read_byte.should eq(0x10)
        buffer.read_byte.should eq(0x01)
      end

      it 'removes the byte from the buffer' do
        buffer.append("\x10\x01")
        buffer.read_byte
        buffer.should eq(ByteBuffer.new("\x01"))
      end

      it 'raises an error if there are no bytes' do
        expect { buffer.read_byte }.to raise_error(RangeError)
      end

      it 'can interpret the byte as signed' do
        buffer.append("\x81\x02")
        buffer.read_byte(true).should eq(-127)
        buffer.read_byte(true).should eq(2)
      end
    end

    describe '#update' do
      it 'changes the bytes at the specified location' do
        buffer.append('foo bar')
        buffer.update(4, 'baz')
        buffer.to_s.should eq('foo baz')
      end

      it 'handles updates after a read' do
        buffer.append('foo bar')
        buffer.read(1)
        buffer.update(3, 'baz')
        buffer.to_s.should eq('oo baz')
      end

      it 'handles updates after multiple reads and appends' do
        buffer.append('foo bar')
        buffer.read(1)
        buffer.append('x')
        buffer.update(4, 'baz')
        buffer.append('yyyy')
        buffer.read(1)
        buffer.to_s.should eq('o bbazyyyy')
      end

      it 'returns itself' do
        buffer.append('foo')
        buffer.update(0, 'bar').should equal(buffer)
      end
    end

    describe '#dup' do
      it 'returns a copy' do
        buffer.append('hello world')
        copy = buffer.dup
        copy.should eql(buffer)
      end

      it 'returns a copy which can be modified without modifying the original' do
        buffer.append('hello world')
        copy = buffer.dup
        copy.append('goodbye')
        copy.should_not eql(buffer)
      end
    end

    describe '#cheap_peek' do
      it 'returns a prefix of the buffer' do
        buffer.append('foo')
        buffer.append('bar')
        buffer.read_byte
        buffer.append('hello')
        x = buffer.cheap_peek
        x.bytesize.should be > 0
        x.bytesize.should be <= buffer.bytesize
        buffer.to_str.should start_with(x)
      end

      it 'considers contents in the write when read buffer consumed' do
        buffer.append('foo')
        buffer.append('bar')
        buffer.read_byte
        buffer.discard(5)
        buffer.append('hello')
        x = buffer.cheap_peek
        x.bytesize.should be > 0
        x.bytesize.should be <= buffer.bytesize
        buffer.to_str.should start_with(x)
      end

      it 'returns nil in readonly mode when read buffer is consumed' do
        buffer.append('foo')
        buffer.append('bar')
        buffer.read_byte
        buffer.discard(5)
        buffer.append('hello')
        x = buffer.cheap_peek(true)
        x.should be_nil
      end
    end

    describe '#getbyte' do
      it 'returns the nth byte interpreted as an int' do
        buffer.append("\x80\x01")
        expect(buffer.getbyte(0)).to eq(0x80)
        expect(buffer.getbyte(1)).to eq(0x01)
      end

      it 'returns nil if there are no bytes' do
        expect(buffer.getbyte(0)).to be_nil
      end

      it 'returns nil if the index goes beyond the buffer' do
        buffer.append("\x80\x01")
        expect(buffer.getbyte(2)).to be_nil
      end

      it 'handles interleaved writes' do
        buffer.append("\x80\x01")
        buffer.read_byte
        buffer.append("\x81\x02")
        expect(buffer.getbyte(0)).to eq(0x01)
        expect(buffer.getbyte(1)).to eq(0x81)
      end

      it 'can interpret the byte as signed' do
        buffer.append("\x80\x02")
        expect(buffer.getbyte(0, true)).to eq(-128)
        expect(buffer.getbyte(1, true)).to eq(2)
      end
    end

    describe '#index' do
      it 'returns the first index of the specified substring' do
        buffer.append('fizz buzz')
        buffer.index('zz').should eq(2)
      end

      it 'returns the first index of the specified substring, after the specified index' do
        buffer.append('fizz buzz')
        buffer.index('zz', 3).should eq(7)
      end

      it 'returns nil when the substring is not found' do
        buffer.append('hello world')
        buffer.index('zz').should be_nil
      end

      it 'returns the first index of the specified substring after the buffer has been modified' do
        buffer.append('foo bar')
        buffer.read(1)
        buffer.append(' baz baz')
        buffer.index('baz', 8).should eq(11)
      end

      it 'returns the first index when the matching substring spans the read and write buffer' do
        buffer.append('foo bar')
        buffer.read(1)
        buffer.append('bar barbar')
        buffer.index('barbar', 0).should eq(3)
      end

      it 'returns nil when the substring does not fit in the search space' do
        buffer.append('foo')
        buffer.read(1)
        buffer.append('bar')
        buffer.index('bar', 3).should be_nil
      end
    end

    context 'when reading and appending' do
      it 'handles heavy churn' do
        1000.times do
          buffer.append('x' * 6)
          buffer.read_byte
          buffer.append('y')
          buffer.read_int
          buffer.read_short
          buffer.append('z' * 4)
          buffer.read_byte
          buffer.append('z')
          buffer.read_int
          buffer.should be_empty
        end
      end
    end
  end
end