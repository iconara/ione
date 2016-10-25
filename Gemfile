source 'https://rubygems.org/'

gemspec

gem 'rake'

group :development do
  platforms :mri do
    gem 'yard',       '~> 0.8.0'
    gem 'redcarpet',  '~> 3.1.0'
  end
end

group :http_client_example do
  gem 'http_parser.rb', '~> 0.6.0'
end

group :test do
  gem 'rspec',      '~> 2.14.0'
  gem 'simplecov',  '~> 0.8.0'
  gem 'coveralls',  '~> 0.7.0'
  
  platforms :ruby_19, :jruby do
    gem 'mime-types', '< 3.0'
  end
end