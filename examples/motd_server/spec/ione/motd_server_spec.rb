# encoding: utf-8

require 'ione/motd_server'
require 'tempfile'


module Ione
  describe MotdServer do
    let :server do
      described_class.new(port, motd_path)
    end

    let :port do
      rand(2**15) + 2**15
    end

    let :motd_path do
      f = Tempfile.new('motd')
      f.puts('Lorem ipsum dolor sit')
      f.close
      f.path
    end

    context 'when accepting a connection' do
      before do
        server.start.value
      end

      after do
        server.stop.value
      end

      it 'responds with the contents of the motd file and closes the connection' do
        socket = TCPSocket.new('127.0.0.1', port)
        result = socket.read
        result.should eq "Lorem ipsum dolor sit\n"
      end
    end
  end
end