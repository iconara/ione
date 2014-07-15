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
      double(:app)
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

      it 'responds with body returned by the app' do
        app.stub(:call).and_return([200, {}, ['world']])
        response = client.get("http://localhost:#{port}/hello").value
        response.body.should eq('world')
      end

      it 'responds with the status code returned by the app' do
        app.stub(:call).and_return([200, {}, ['world']])
        response = client.get("http://localhost:#{port}/hello").value
        response.status.should eq(200)
        app.stub(:call).and_return([400, {}, ['world']])
        response = client.get("http://localhost:#{port}/hello").value
        response.status.should eq(400)
      end

      it 'responds with the headers returned by the app' do
        app.stub(:call).and_return([200, {'X-Foo' => 'baz', 'ETag' => '98'}, ['world']])
        response = client.get("http://localhost:#{port}/hello").value
        response.headers.should include('X-Foo' => 'baz', 'ETag' => '98')
      end

      it 'responds with Internal Server Error when the app raises an error' do
        app.stub(:call).and_raise(StandardError.new('bork'))
        response = client.get("http://localhost:#{port}/hello").value
        response.status.should eq(500)
      end

      it 'responds with Internal Server Error when sending the body raises an error' do
        body = double(:body)
        body.stub(:each).and_raise(StandardError.new('bork'))
        app.stub(:call).and_return([200, {}, body])
        response = client.get("http://localhost:#{port}/hello").value
        response.status.should eq(500)
      end

      it 'responds with a chunked response when the body is larger than a few bytes' do
        body = %w[
          Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer et
          hendrerit elit. Vivamus ac laoreet nibh. In nec lacinia risus. Donec
          leo velit, consequat eget tincidunt nec, tincidunt quis tellus. Cras
          eget tincidunt leo. Cras facilisis, magna blandit luctus rutrum, est
          dui egestas quam, id placerat erat enim ut elit. In faucibus augue
          quis eros vehicula, id blandit dolor porttitor. Duis amet.
        ]
        app.stub(:call).and_return([200, {}, body])
        response = client.get("http://localhost:#{port}/hello").value
        response.headers['Transfer-Encoding'].should eq('chunked')
      end

      it 'responds a non-chunked response when the body is small' do
        app.stub(:call).and_return([200, {}, %w[Lorem ipsum dolor sit]])
        response = client.get("http://localhost:#{port}/hello").value
        response.body.should eq('Loremipsumdolorsit')
        response.headers.should include('Content-Length' => '18')
        response.headers.should_not have_key('Transfer-Encoding')
      end

      it 'correctly handles the length of bodies with multi-byte characters' do
        app.stub(:call).and_return([200, {}, ['Lörëm ipsüm dölör sït']])
        response = client.get("http://localhost:#{port}/hello").value
        response.body.force_encoding(::Encoding::UTF_8).should eq('Lörëm ipsüm dölör sït')
        response.headers.should include('Content-Length' => '27')
      end

      it 'correctly handles the length of bodies with multi-byte characters when chunking' do
        app.stub(:call).and_return([200, {}, ['Lörëm ipsüm dölör sït'] * 20])
        response = client.get("http://localhost:#{port}/hello").value
        response.body.force_encoding(::Encoding::UTF_8).should eq('Lörëm ipsüm dölör sït' * 20)
      end

      it 'handles an empty body' do
        app.stub(:call).and_return([200, {}, []])
        response = client.get("http://localhost:#{port}/hello").value
        response.body.should be_empty
        response.headers.should include('Content-Length' => '0')
        response.headers.should_not have_key('Transfer-Encoding')
      end

      it 'handles body that only responds to #each' do
        body = double(:body)
        body.stub(:each).and_yield('foo').and_yield('bar').and_yield('baz')
        app.stub(:call).and_return([200, {}, body])
        response = client.get("http://localhost:#{port}/hello").value
        response.body.should eq('foobarbaz')
        response.headers['Transfer-Encoding'].should eq('chunked')
      end

      it 'exposes the request method to the app' do
        env = nil
        app.stub(:call) do |e|
          env = e
          [200, {}, []]
        end
        client.get("http://localhost:#{port}/hello").value
        env.should include('REQUEST_METHOD' => 'GET')
      end

      it 'exposes the request path to the app' do
        env = nil
        app.stub(:call) do |e|
          env = e
          [200, {}, []]
        end
        client.get("http://localhost:#{port}/hello/world?foo=bar").value
        env.should include('REQUEST_PATH' => '/hello/world')
      end

      it 'exposes the query string to the app' do
        env = nil
        app.stub(:call) do |e|
          env = e
          [200, {}, []]
        end
        client.get("http://localhost:#{port}/hello/world?foo=bar&baz=qux").value
        env.should include('QUERY_STRING' => 'foo=bar&baz=qux')
      end
    end
  end
end