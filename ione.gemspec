# encoding: utf-8

$: << File.expand_path('../lib', __FILE__)

require 'ione/version'


Gem::Specification.new do |s|
  s.name          = 'ione'
  s.version       = Ione::VERSION.dup
  s.authors       = ['Theo Hultberg']
  s.email         = ['theo@iconara.net']
  s.homepage      = 'http://github.com/iconara/ione'
  s.summary       = %q{Reactive programming framework for Ruby}
  s.description   = %q{Reactive programming framework for Ruby, painless evented IO, futures and an efficient byte buffer}
  s.license       = 'Apache License 2.0'

  s.files         = Dir['lib/**/*.rb', 'README.md', '.yardopts']
  s.test_files    = Dir['spec/**/*.rb']
  s.require_paths = %w(lib)

  s.platform = Gem::Platform::RUBY
  s.required_ruby_version = '>= 1.9.3'
end
