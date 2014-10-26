# encoding: utf-8

require 'spec_helper'
require 'ione/io/connection_common'


module Ione
  module Io
    describe ServerConnection do
      let :handler do
        described_class.new(socket, 'example.com', 4321, unblocker)
      end

      let :socket do
        double(:socket, close: nil)
      end

      let :unblocker do
        double(:unblocker, unblock: nil)
      end

      it_behaves_like 'a connection'

      describe '#to_io' do
        it 'returns the socket' do
          handler.to_io.should equal(socket)
        end

        it 'returns nil when the socket is closed' do
          socket.stub(:close)
          handler.close
          handler.to_io.should be_nil
        end
      end
    end
  end
end
