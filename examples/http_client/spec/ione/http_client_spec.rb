# encoding: utf-8

require 'webrick'
require 'open-uri'
require 'logger'
require 'ione/http_client'


module Ione
  describe HttpClient do
    let :client do
      described_class.new
    end

    let :port do
      rand(2**15) + 2**15
    end

    let :server do
      WEBrick::HTTPServer.new(
        :Port => port,
        :Logger => Logger.new(File.open('/dev/null', 'w')),
        :AccessLog => File.open('/dev/null', 'w')
      )
    end

    let :handler do
      HttpClientSpec::Servlet
    end

    before do
      server.mount('/', handler)
      Thread.start { server.start }
      begin
        open("http://localhost:#{port}/")
      rescue OpenURI::HTTPError
        retry
      end
    end

    after do
      server.shutdown
    end

    before do
      client.start
    end

    after do
      client.stop
    end

    it 'sends a GET request' do
      f = client.get("http://localhost:#{port}/helloworld")
      response = f.value
      response.status.should == 200
      response.body.should == 'Hello, World!'
    end

    it 'sends an GET request with parameters' do
      response = client.get("http://localhost:#{port}/fizzbuzz?n=3").value
      response.body.should == 'buzz'
      response = client.get("http://localhost:#{port}/fizzbuzz?n=4").value
      response.body.should == '4'
    end

    it 'sends a GET request with headers' do
      response = client.get("http://localhost:#{port}/helloworld", 'Accept' => 'text/html').value
      response.headers.should include('Content-Type' => 'text/html')
      response.body.should == '<h1>Hello, World!</h1>'
    end

    it 'sends a headers as strings' do
      response = client.get("http://localhost:#{port}/helloworld", 'X-Echo' => 7).value
      response.headers.should include('X-Echo' => '7')
    end
  end
end

module HttpClientSpec
  class Servlet < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(request, response)
      response['Content-Type'] = 'text/plain'
      case request.path_info
      when '/helloworld'
        response.body = 'Hello, World!'
        response['X-Echo'] = request['X-Echo'] if request['X-Echo']
        case request.header['accept'].first
        when 'text/html'
          response.body = "<h1>#{response.body}</h1>"
          response['Content-Type'] = 'text/html'
        end
      when '/fizzbuzz'
        n = request.query_string.scan(/n=(\d+)/).flatten.first.to_i
        response.body = ''
        response.body << 'fizz' if n % 5 == 0
        response.body << 'buzz' if n % 3 == 0
        response.body << n.to_s if response.body.empty?
      else
        response.body = ''
      end
      response.status = 200
    end
  end
end