# encoding: utf-8

require 'rspec/core/rake_task'
require 'bundler/gem_helper'


task :default => :spec

RSpec::Core::RakeTask.new(:spec) do |r|
  options = File.readlines('.rspec').map(&:chomp)
  if (pattern = options.find { |o| o.start_with?('--pattern') })
    options.delete(pattern)
    r.pattern = pattern.sub(/^--pattern\s+(['"']?)(.+)\1$/, '\2')
  end
  r.ruby_opts, r.rspec_opts = options.partition { |o| o.start_with?('-I') }
end

namespace :bundler do
  Bundler::GemHelper.install_tasks
end

desc 'Tag & release the gem'
task :release => [:spec, 'bundler:release']
