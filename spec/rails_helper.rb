# spec/rails_helper.rb
require 'spec_helper'
require 'dotenv/load'

ENV['RAILS_ENV'] ||= 'test'

require_relative '../test/dummy/config/environment'
require 'rspec/rails'


require 'vcr'
require 'webmock/rspec'

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
end
