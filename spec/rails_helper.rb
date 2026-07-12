# spec/rails_helper.rb
require 'spec_helper'
require 'dotenv/load'

ENV['RAILS_ENV'] ||= 'test'
ENV['OPENAI_ACCESS_TOKEN'] ||= 'sk-test-vcr-dummy-key'

require_relative '../test/dummy/config/environment'
require 'rspec/rails'


require 'vcr'
require 'webmock/rspec'

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.filter_sensitive_data("<OPENAI_ACCESS_TOKEN>") { ENV["OPENAI_ACCESS_TOKEN"] }
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.filter_run_excluding :vcr if ENV['CI']
end
