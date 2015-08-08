# encoding: utf-8

require 'spec_helper'


module Ione
  describe NullThreadPool do
    let :thread_pool do
      described_class.new
    end

    describe '#submit' do
      it 'calls the block immediately' do
        called = false
        thread_pool.submit { called = true }
        called.should be_true
      end

      it 'returns a resolved future with the result of the block' do
        f = thread_pool.submit { 2 * 4 }
        f.value.should eq(8)
      end
    end
  end
end
