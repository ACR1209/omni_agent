require_relative "../spec_helper"
require "active_support"
require_relative "../../lib/omni_agent"
require_relative "../../lib/omni_agent/configuration"

RSpec.describe OmniAgent::Configuration do
  before do
    OmniAgent.instance_variable_set(:@configuration, nil)
  end

  after do
    OmniAgent.instance_variable_set(:@configuration, nil)
  end

  describe "defaults" do
    it "uses :openai as the default provider" do
      expect(OmniAgent.configuration.default_provider).to eq(:openai)
    end
  end

  describe ".configure" do
    it "allows an initializer-style configure block to override the default provider" do
      OmniAgent.configure do |config|
        config.default_provider = :test_provider
      end

      expect(OmniAgent.configuration.default_provider).to eq(:test_provider)
    end
  end
end
