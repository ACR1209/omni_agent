require "bundler/setup"
require "rspec/core/rake_task"

APP_RAKEFILE = File.expand_path("test/dummy/Rakefile", __dir__)
load "rails/tasks/engine.rake"

require "bundler/gem_tasks"

# release-please already tags and pushes releases, and CI checks out a
# detached HEAD, so the default `release` task's git tag/push step
# (release:guard_clean, release:source_control_push) always fails there.
# Redefine it to just build + push the gem.
Rake::Task["release"].clear
task release: [ "build", "release:rubygem_push" ]

RSpec::Core::RakeTask.new(:spec)

task default: :spec
