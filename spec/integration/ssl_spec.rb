# encoding: utf-8

require 'spec_helper'


describe 'SSL' do
  let :io_reactor do
    Ione::Io::IoReactor.new
  end

  let :port do
    2**15 + rand(2**15)
  end

  let :ssl_key do
    OpenSSL::PKey::RSA.new(2048)
  end

  let :ssl_cert do
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    name = OpenSSL::X509::Name.new([['CN', 'localhost']])
    cert.subject = name
    cert.issuer = name
    cert.not_before = Time.now
    cert.not_after = Time.now + (365*24*60*60)
    cert.public_key = ssl_key.public_key
    cert.sign(ssl_key, OpenSSL::Digest::SHA1.new)
    cert
  end

  let :ssl_context do
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.cert = ssl_cert
    ctx.key = ssl_key
    ctx
  end

  let :server_received_data do
    Ione::ByteBuffer.new
  end

  let :client_received_data do
    Ione::ByteBuffer.new
  end

  def start_server
    ssl_context = OpenSSL::SSL::SSLContext.new
    ssl_context.key = OpenSSL::PKey::RSA.new(ssl_key)
    ssl_context.cert = OpenSSL::X509::Certificate.new(ssl_cert)

    f = io_reactor.start
    f = f.flat_map do
      io_reactor.bind(ENV['SERVER_HOST'], port, ssl: ssl_context) do |acceptor|
        acceptor.on_accept do |connection|
          connection.on_data do |data|
            server_received_data << data
            connection.write(data.reverse)
          end
        end
      end
    end
    f
  end

  it 'establishes an encrypted connection' do
    ssl_context = OpenSSL::SSL::SSLContext.new
    ssl_context.cert = OpenSSL::X509::Certificate.new(ssl_cert)

    response_received = Ione::Promise.new
    f = start_server
    f = f.flat_map do
      io_reactor.connect(ENV['SERVER_HOST'], port, ssl: ssl_context)
    end
    client = f.value
    client.on_data do |data|
      client_received_data << data
      response_received.fulfill(data)
    end
    client.write('hello world')
    response_received.future.value
    server_received_data.to_s.should == 'hello world'
    client_received_data.to_s.should == 'dlrow olleh'
  end

  it 'fails to send a message when not using encryption' do
    f = start_server
    f = f.flat_map do
      io_reactor.connect(ENV['SERVER_HOST'], port)
    end
    client = f.value
    client.write('hello world')
    await { client.closed? }
    client.should be_closed
  end
end
