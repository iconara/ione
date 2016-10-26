# encoding: utf-8

require 'webrick'
require 'webrick/https'
require 'net/https'
require 'logger'
require 'ione/http_client'


module Ione
  describe HttpClient do
    let :port do
      rand(2**15) + 2**15
    end

    let :handler do
      HttpClientSpec::Servlet
    end

    let :base_uri do
      "#{scheme}://#{WEBrick::Utils::getservername}:#{port}"
    end

    def await_server_start
      attempts = 10
      begin
        http = Net::HTTP.new(WEBrick::Utils::getservername, port)
        if scheme == 'https'
          http.use_ssl = true
          http.cert_store = cert_store
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end
        http.request(Net::HTTP::Get.new('/'))
      rescue Errno::ECONNREFUSED, Errno::ENOTCONN, OpenSSL::SSL::SSLError
        attempts -= 1
        if attempts > 0
          sleep(0.01)
          retry
        else
          fail('Server failed to start')
        end
      end
    end

    before do
      server.mount('/', handler)
      Thread.start { server.start }
      await_server_start
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

    shared_examples 'http_requests' do
      it 'sends a GET request' do
        f = client.get("#{base_uri}/helloworld")
        response = f.value
        response.status.should eq(200)
        response.body.should eq('Hello, World!')
      end

      it 'sends an GET request with parameters' do
        response = client.get("#{base_uri}/fizzbuzz?n=3").value
        response.body.should eq('buzz')
        response = client.get("#{base_uri}/fizzbuzz?n=4").value
        response.body.should eq('4')
      end

      it 'sends a GET request with headers' do
        response = client.get("#{base_uri}/helloworld", 'Accept' => 'text/html').value
        response.headers.should include('Content-Type' => 'text/html')
        response.body.should eq('<h1>Hello, World!</h1>')
      end
    end

    context 'over HTTP' do
      let :client do
        described_class.new
      end

      let :scheme do
        'http'
      end

      let :server do
        WEBrick::HTTPServer.new(
          :Port => port,
          :Logger => Logger.new(File.open('/dev/null', 'w')),
          :AccessLog => File.open('/dev/null', 'w')
        )
      end

      include_examples 'http_requests'
    end

    context 'over HTTPS' do
      let :client do
        described_class.new(cert_store)
      end

      let :scheme do
        'https'
      end

      let :root_ca_and_key do
        HttpClientSpec.create_root_ca([['O', 'Ione']])
      end

      let :root_ca do
        root_ca_and_key[0]
      end

      let :cert_and_key do
        HttpClientSpec.create_cert(*root_ca_and_key, [['CN', WEBrick::Utils::getservername]])
      end

      let :cert do
        cert_and_key[0]
      end

      let :key do
        cert_and_key[1]
      end

      let :cert_store do
        s = OpenSSL::X509::Store.new
        s.add_cert(root_ca)
        s
      end

      let :server do
        WEBrick::HTTPServer.new(
          :Port => port,
          :SSLEnable => true,
          :SSLCertificate => cert,
          :SSLPrivateKey => key,
          :Logger => Logger.new(File.open('/dev/null', 'w')),
          :AccessLog => File.open('/dev/null', 'w')
        )
      end

      include_examples 'http_requests'
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

  def self.create_root_ca(cn)
    key = OpenSSL::PKey::RSA.new(1024)
    root_ca = OpenSSL::X509::Certificate.new
    root_ca.version = 2
    root_ca.serial = 1
    root_ca.subject = OpenSSL::X509::Name.new(cn)
    root_ca.issuer = root_ca.subject
    root_ca.public_key = key.public_key
    root_ca.not_before = Time.now
    root_ca.not_after = root_ca.not_before + 86400
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = root_ca
    ef.issuer_certificate = root_ca
    root_ca.add_extension(ef.create_extension('basicConstraints', 'CA:TRUE', true))
    root_ca.add_extension(ef.create_extension('keyUsage', 'keyCertSign, cRLSign', true))
    root_ca.add_extension(ef.create_extension('subjectKeyIdentifier', 'hash', false))
    root_ca.add_extension(ef.create_extension('authorityKeyIdentifier', 'keyid:always', false))
    root_ca.sign(key, OpenSSL::Digest::SHA256.new)
    [root_ca, key]
  end

  def self.create_cert(root_ca, root_key, subject)
    key = OpenSSL::PKey::RSA.new(1024)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 2
    cert.subject = OpenSSL::X509::Name.new(subject)
    cert.issuer = root_ca.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now
    cert.not_after = cert.not_before + 86400
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = root_ca
    cert.add_extension(ef.create_extension('keyUsage', 'digitalSignature', true))
    cert.add_extension(ef.create_extension('subjectKeyIdentifier', 'hash', false))
    cert.sign(root_key, OpenSSL::Digest::SHA256.new)
    [cert, key]
  end
end
