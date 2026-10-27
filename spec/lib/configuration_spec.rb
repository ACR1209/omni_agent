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

    it "uses gpt-4o-mini as the default model" do
      expect(OmniAgent.configuration.default_model).to eq("gpt-4o-mini")
    end

    it "leaves the embedding provider and model unset so they fall back to the provider defaults" do
      expect(OmniAgent.configuration.embedding_provider).to be_nil
      expect(OmniAgent.configuration.embedding_model).to be_nil
    end

    it "has no embedding job options" do
      expect(OmniAgent.configuration.embedding_job_options).to eq({})
    end

    it "has no extra document loaders" do
      expect(OmniAgent.configuration.document_loaders).to eq({})
    end
  end

  describe "#embedding_job_options=" do
    it "rejects options ActiveJob's set doesn't take" do
      expect { OmniAgent.configuration.embedding_job_options = { queue_name: :embeddings } }
        .to raise_error(ArgumentError, /Unknown embedding_job_options option :queue_name/)
    end
  end

  describe ".configure" do
    it "allows an initializer-style configure block to override the default provider" do
      OmniAgent.configure do |config|
        config.default_provider = :test_provider
      end

      expect(OmniAgent.configuration.default_provider).to eq(:test_provider)
    end

    it "allows an initializer-style configure block to override the default model" do
      OmniAgent.configure do |config|
        config.default_model = "gpt-4.1-mini"
      end

      expect(OmniAgent.configuration.default_model).to eq("gpt-4.1-mini")
    end
  end
end
