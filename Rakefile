# encoding: utf-8

require 'rspec/core/rake_task'
require 'bundler/gem_helper'


task :default => 'spec:all'

namespace :spec do
  desc 'Run all tests'
  task :all

  desc 'Run core tests'
  RSpec::Core::RakeTask.new(:core)
  task :all => :core

  FileList['examples/*/spec'].each do |path|
    name = path.split('/')[1]
    desc "Run #{name} example tests"
    task name do
      Dir.chdir(File.dirname(path)) do
        Rake::Task["spec:#{name}_spec"].invoke
      end
    end
    desc ''
    RSpec::Core::RakeTask.new("#{name}_spec")
    task :all => name
  end
end

namespace :bundler do
  Bundler::GemHelper.install_tasks
end

desc 'Tag & release the gem'
task :release => ['spec:all', 'bundler:release']
