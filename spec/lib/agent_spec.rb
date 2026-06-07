require_relative "../spec_helper"
require_relative "../../lib/omni_agent"
require_relative "../../lib/omni_agent/agent"
require_relative "../../lib/omni_agent/errors"

RSpec.describe OmniAgent::Agent do
  around do |example|
    previous_config = OmniAgent.instance_variable_get(:@configuration)
    OmniAgent.instance_variable_set(:@configuration, nil)
    example.run
    OmniAgent.instance_variable_set(:@configuration, previous_config)
  end

  let(:provider_class) do
    Class.new do
      attr_reader :model

      def initialize(model: nil)
        @model = model
      end
    end
  end

  before do
    allow(OmniAgent::Providers).to receive(:registry).and_return(test_provider: provider_class)
  end

  it "uses OmniAgent.configuration.default_provider when agent class does not define a provider" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class)
    agent = agent_class.new

    expect(agent.provider).to be_a(provider_class)
    expect(agent.provider.model).to be_nil
  end

  it "allows overriding only the model while using the configured default provider" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class)
    agent = agent_class.new(model_override: "gpt-custom")

    expect(agent.provider).to be_a(provider_class)
    expect(agent.provider.model).to eq("gpt-custom")
  end

  it "allows setting model via use_model without passing model through provider" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class) do
      use_model "gpt-from-use-model"
    end
    agent = agent_class.new

    expect(agent.provider).to be_a(provider_class)
    expect(agent.provider.model).to eq("gpt-from-use-model")
  end

  it "raises when provider is declared after use_model" do
    expect do
      Class.new(described_class) do
        use_model "gpt-ordered"
        provider :test_provider
      end
    end.to raise_error(OmniAgent::Error, /Cannot combine `provider` and `use_model`/)
  end

  it "raises when use_model is declared after provider" do
    expect do
      Class.new(described_class) do
        provider :test_provider, model: "gpt-provider"
        use_model "gpt-use-model"
      end
    end.to raise_error(OmniAgent::Error, /Cannot combine `provider` and `use_model`/)
  end
end
