source 'https://rubygems.org/'

gemspec

gem 'rake'

group :development do
  platforms :mri do
    gem 'yard'
    gem 'redcarpet'
  end
end

group :http_client_example do
  gem 'http_parser.rb'
end

group :http_server_example do
  gem 'puma'
end

group :test do
  gem 'rspec'
  gem 'simplecov'
  gem 'coveralls'
end