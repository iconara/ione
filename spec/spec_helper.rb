# encoding: utf-8

require 'ione'

require 'support/fake_server'
require 'support/await_helper'

ENV['SERVER_HOST'] ||= '127.0.0.1'.freeze
