# encoding: utf-8

require 'ione/redis_client'


module Ione
  describe RedisClient do
    let :client do
      begin
        described_class.connect(ENV['SERVER_HOST'], 6379).value
      rescue
        nil
      end
    end

    it 'can set a value' do
      pending('Redis not running', unless: client)
      response = client.set('foo', 'bar').value
      response.should eq('OK')
    end

    it 'can get a value' do
      pending('Redis not running', unless: client)
      f = client.set('foo', 'bar').flat_map do
        client.get('foo')
      end
      f.value.should eq('bar')
    end

    it 'can delete values' do
      pending('Redis not running', unless: client)
      f = client.set('hello', 'world').flat_map do
        client.del('hello')
      end
      f.value.should eq(1)
    end

    it 'handles nil values' do
      pending('Redis not running', unless: client)
      f = client.del('hello').flat_map do
        client.get('hello')
      end
      f.value.should be_nil
    end

    it 'handles errors' do
      pending('Redis not running', unless: client)
      f = client.set('foo')
      expect { f.value }.to raise_error("ERR wrong number of arguments for 'set' command")
    end

    it 'handles replies with multiple elements' do
      pending('Redis not running', unless: client)
      f = client.del('stuff')
      f.value
      f = client.rpush('stuff', 'hello', 'world')
      f.value.should eq(2)
      f = client.lrange('stuff', 0, 2)
      f.value.should eq(['hello', 'world'])
    end

    it 'handles nil values when reading multiple elements' do
      pending('Redis not running', unless: client)
      client.del('things')
      client.hset('things', 'hello', 'world')
      f = client.hmget('things', 'hello', 'foo')
      f.value.should eq(['world', nil])
    end
  end
end
