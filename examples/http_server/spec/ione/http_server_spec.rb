# encoding: utf-8

require 'ione/http_server'
require 'ione/http_client'


module Ione
  describe HttpServer do
    let :server do
      described_class.new(port, app)
    end

    let :port do
      rand(2**15) + 2**15
    end

    let :app do
      lambda { |env| [200, {}, [env['REQUEST_PATH']]] }
    end

    let :client do
      HttpClient.new
    end

    context 'handles a GET request' do
      before do
        server.start.value
        client.start.value
      end

      after do
        client.stop.value
        server.stop.value
      end

      it 'responds with the requested path' do
        f = client.get("http://localhost:#{port}/helloworld", 'Accept' => 'text/plain')
        response = f.value
        response.status.should == 200
        response.body.should == '/helloworld'
      end
    end
  end
end