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

      it 'handles a body that only responds to #each' do
        body = double(:body)
        body.stub(:each).and_yield('foo').and_yield('bar').and_yield('baz')
        app.stub(:call).and_return([200, {}, body])
        response = client.get("http://localhost:#{port}/hello").value
        response.body.should eq('foobarbaz')
        response.headers['Transfer-Encoding'].should eq('chunked')
      end

      context 'for Rack compliance the environment' do
        let :env do
          {}
        end

        before do
          app.stub(:call) do |e|
            env.replace(e)
            [200, {}, []]
          end
          client.get("http://localhost:#{port}/hello/world?foo=bar&baz=qux").value
        end

        it 'contains the request method under REQUEST_METHOD' do
          env.should include('REQUEST_METHOD' => 'GET')
        end

        it 'contains the request path under REQUEST_PATH and PATH_INFO' do
          env.should include('REQUEST_PATH' => '/hello/world', 'PATH_INFO' => '/hello/world')
        end

        it 'contains the query string under QUERY_STRING' do
          env.should include('QUERY_STRING' => 'foo=bar&baz=qux')
        end

        it 'contains the server host and port under SERVER_NAME and SERVER_PORT' do
          env.should include('SERVER_NAME' => Socket.gethostname, 'SERVER_PORT' => port)
        end

        it 'contains an empty string under SCRIPT_NAME' do
          env.should include('SCRIPT_NAME' => '')
        end

        it 'contains an entry for each request header, uppercased and prefixed with "HTTP_"' do
          app.stub(:call) do |e|
            env.replace(e)
            [200, {}, []]
          end
          client.get("http://localhost:#{port}/hello/world?foo=bar&baz=qux", {'Accept' => 'text/plain', 'X-Forwarded-For' => '1.2.3.4'}).value
          env.should include('HTTP_ACCEPT' => 'text/plain', 'HTTP_X_FORWARDED_FOR' => '1.2.3.4')
        end

        it 'contains CONTENT_{LENGTH,TYPE} and not HTTP_CONTENT_{LENGTH,TYPE}' do
          app.stub(:call) do |e|
            env.replace(e)
            [200, {}, []]
          end
          client.get("http://localhost:#{port}/hello/world?foo=bar&baz=qux", {'Content-Type' => 'text/plain', 'Content-Length' => 3}).value
          env.should include('CONTENT_TYPE' => 'text/plain', 'CONTENT_LENGTH' => '3')
        end

        it 'contains the Rack version' do
          env.should include('rack.version' => Rack::VERSION)
        end

        it 'contains the URL scheme' do
          env.should include('rack.url_scheme' => 'http')
        end

        it 'contains info about the execution model' do
          env.should include('rack.multithread' => true, 'rack.multiprocess' => false, 'rack.run_once' => false)
        end

        it 'contains info about hijack support' do
          env.should include('rack.hijack?' => false, 'rack.hijack' => nil, 'rack.hijack_io' => nil)
        end
      end
    end
  end
end