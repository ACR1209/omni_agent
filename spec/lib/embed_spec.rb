require_relative "../spec_helper"
require_relative "../../lib/omni_agent"

RSpec.describe "OmniAgent.embed" do
  let(:provider) { instance_double(OmniAgent::Providers::Mock) }

  before do
    OmniAgent.instance_variable_set(:@configuration, nil)
    OmniAgent.configure { |config| config.default_provider = :mock }
  end

  after do
    OmniAgent.instance_variable_set(:@configuration, nil)
  end

  it "returns a single vector for a single string" do
    vector = OmniAgent.embed("hello")

    expect(vector).to eq(OmniAgent::Providers::Mock.new.embed([ "hello" ]).first)
  end

  it "returns one vector per text for an array" do
    vectors = OmniAgent.embed([ "a", "b" ])

    expect(vectors).to eq(OmniAgent::Providers::Mock.new.embed([ "a", "b" ]))
  end

  it "uses the configured embedding provider and model over the chat defaults" do
    OmniAgent.configure do |config|
      config.default_provider = :openai
      config.embedding_provider = :mock
      config.embedding_model = "embed-v2"
    end
    allow(OmniAgent::Providers::Mock).to receive(:new).and_return(provider)
    expect(provider).to receive(:embed).with([ "hello" ], model: "embed-v2").and_return([ [ 0.1 ] ])

    expect(OmniAgent.embed("hello")).to eq([ 0.1 ])
  end

  it "lets provider: and model: override the configuration per call" do
    OmniAgent.configure { |config| config.embedding_model = "embed-v2" }
    allow(OmniAgent::Providers::Mock).to receive(:new).and_return(provider)
    expect(provider).to receive(:embed).with([ "hello" ], model: "embed-v3").and_return([ [ 0.1 ] ])

    OmniAgent.embed("hello", provider: :mock, model: "embed-v3")
  end

  it "raises UnknownProviderError for an unregistered provider" do
    expect { OmniAgent.embed("hello", provider: :nope) }
      .to raise_error(OmniAgent::UnknownProviderError, /Unknown provider :nope/)
  end
end
