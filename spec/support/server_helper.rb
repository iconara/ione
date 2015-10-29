# encoding: utf-8

module ServerHelper
  def with_server
    TCPServer.open(0) do |server|
      thread = Thread.start { server.accept }
      yield server.addr[3], server.addr[1]
      thread.value
    end
  end
end

RSpec.configure do |c|
  c.include(ServerHelper)
end
