# encoding: utf-8

Warning[:deprecated] = true # Enable ruby deprecation warnings

ENV['SERVER_HOST'] ||= '127.0.0.1'.freeze

require 'bundler/setup'

require 'support/fake_server'
require 'support/await_helper'
require 'support/server_helper'

unless ENV['COVERAGE'] == 'no' || RUBY_ENGINE == 'rbx'
  require 'coveralls'
  require 'simplecov'

  if ENV.include?('TRAVIS')
    Coveralls.wear!
    SimpleCov.formatter = Coveralls::SimpleCov::Formatter
  end

  SimpleCov.start do
    add_group 'Source', 'lib'
    add_group 'Unit tests', 'spec/cql'
    add_group 'Integration tests', 'spec/integration'
  end
end

RSpec.configure do |config|
  config.warnings = true
  config.expect_with :rspec do |expectations|
    expectations.syntax = [:should, :expect]
  end
  config.mock_with :rspec do |mocks|
    mocks.syntax = [:should, :expect]
  end
end

require 'ione'
