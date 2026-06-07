require "bundler/setup"
require "rspec/core/rake_task"

APP_RAKEFILE = File.expand_path("test/dummy/Rakefile", __dir__)
load "rails/tasks/engine.rake"

require "bundler/gem_tasks"

RSpec::Core::RakeTask.new(:spec)

task default: :spec
