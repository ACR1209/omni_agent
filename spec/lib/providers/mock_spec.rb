require_relative "../../spec_helper"
require_relative "../../../lib/omni_agent/providers/base"
require_relative "../../../lib/omni_agent/providers/response"
require_relative "../../../lib/omni_agent/providers/mock"
require_relative "../../../lib/omni_agent/providers"

RSpec.describe OmniAgent::Providers::Mock do
  describe "#chat" do
    it "always returns Lorem Ipsum" do
      provider = described_class.new

      response = provider.chat(messages: [ { role: "user", content: "Hello" } ])

      expect(response).to be_a(OmniAgent::Providers::Response)
      expect(response.content).to eq("Lorem ipsum dolor sit amet, consectetur adipiscing elit.")
      expect(response.tool_calls).to eq([])
      expect(response.raw_request).to eq(model: "mock", messages: [ { role: "user", content: "Hello" } ], tools: [])
    end

    it "ignores tools and options" do
      provider = described_class.new(model: "mock-v2")

      response = provider.chat(
        messages: [ { role: "user", content: "Use a tool" } ],
        tools: [ Class.new ],
        temperature: 0.9
      )

      expect(response.content).to eq("Lorem ipsum dolor sit amet, consectetur adipiscing elit.")
    end

    it "raises when history messages are invalid" do
      provider = described_class.new

      expect {
        provider.chat(messages: [ { role: "invalid", content: "Hello" } ])
      }.to raise_error(OmniAgent::Error, /invalid message role/)
    end

    it "emits text events for each word when streaming" do
      provider = described_class.new
      events = []

      response = provider.chat(messages: [ { role: "user", content: "Hello" } ], stream: ->(event) { events << event })

      expect(events).not_to be_empty
      expect(events).to all(be_a(OmniAgent::Streaming::Event))
      expect(events).to all(satisfy(&:text?))
      expect(events.map(&:text).join).to eq("Lorem ipsum dolor sit amet, consectetur adipiscing elit.")
      expect(response.content).to eq("Lorem ipsum dolor sit amet, consectetur adipiscing elit.")
    end

    it "does not stream when no block is given" do
      provider = described_class.new

      expect { provider.chat(messages: [ { role: "user", content: "Hello" } ]) }.not_to raise_error
    end
  end

  describe "configuration" do
    it "uses mock as the default model" do
      provider = described_class.new

      expect(provider.model).to eq("mock")
    end
  end

  describe "registry" do
    it "is registered in OmniAgent::Providers.registry" do
      expect(OmniAgent::Providers.registry[:mock]).to eq(described_class)
    end
  end
end
