require_relative "../../spec_helper"
require_relative "../../../lib/omni_agent/providers/base"

RSpec.describe OmniAgent::Providers::Base do
  class TestProvider < described_class
    def validate_messages(messages, allowed_roles:)
      validate_messages!(messages, allowed_roles: allowed_roles)
    end

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

  describe "#validate_messages!" do
    let(:provider) { TestProvider.new }

    it "validates a well-formed message list" do
      messages = [
        { role: "system", content: "You are helpful" },
        { role: "user", content: "Hi" },
        { role: "assistant", content: "Hello" }
      ]

      expect {
        provider.validate_messages(messages, allowed_roles: %i[system user assistant tool])
      }.not_to raise_error
    end

    it "raises when role is invalid" do
      messages = [ { role: "invalid", content: "Hi" } ]

      expect {
        provider.validate_messages(messages, allowed_roles: %i[user assistant])
      }.to raise_error(OmniAgent::Error, /invalid message role/)
    end

    it "raises when user message is missing content" do
      messages = [ { role: "user" } ]

      expect {
        provider.validate_messages(messages, allowed_roles: %i[user assistant])
      }.to raise_error(OmniAgent::Error, /must include content/)
    end
  end
end
