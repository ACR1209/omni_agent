require_relative "../../spec_helper"
require_relative "../../../lib/providers/base"

RSpec.describe OmniAgents::Providers::Base do
  class TestProvider < described_class
    protected

    def default_api_key
      "default-key"
    end

    def default_model
      "default-model"
    end
  end

  describe "#initialize" do
    it "uses defaults when api_key and model are not provided" do
      provider = TestProvider.new

      expect(provider.model).to eq("default-model")
      expect(provider.instance_variable_get(:@api_key)).to eq("default-key")
    end

    it "uses explicit values when provided" do
      provider = TestProvider.new(api_key: "explicit-key", model: "explicit-model")

      expect(provider.model).to eq("explicit-model")
      expect(provider.instance_variable_get(:@api_key)).to eq("explicit-key")
    end
  end

  describe "#chat" do
    it "raises NotImplementedError by default" do
      provider = TestProvider.new

      expect { provider.chat(messages: []) }.to raise_error(
        NotImplementedError,
        "Providers must implement #chat"
      )
    end
  end
end
