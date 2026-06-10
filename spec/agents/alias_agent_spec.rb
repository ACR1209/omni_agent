require "rails_helper"

RSpec.describe AliasAgent do
  let(:agent) { AliasAgent.new }

  it "loads AliasAgent from the dummy app" do
    expect(described_class.name).to eq("AliasAgent")
  end

  it "uses method entrypoint calls as run aliases and merges base + method prompts" do
    configured_agent = described_class.with(user: "Alice")
    captured_messages = nil

    allow(configured_agent).to receive(:available_tools).and_return([])
    allow(configured_agent.provider).to receive(:chat) do |messages:, tools: [], **_options|
      captured_messages = messages
      OmniAgent::Providers::Response.new(content: "ok", raw_response: {}, tool_calls: [])
    end

    response = configured_agent.summarize("Summarize this", topic: "billing")

    expect(response).to eq("ok")
    expect(configured_agent.last_entrypoint).to eq(:summarize)
    expect(captured_messages.first[:role]).to eq("system")
    expect(captured_messages.first[:content]).to include("You are AliasAgent.")
    expect(captured_messages.first[:content]).to include("Current user: Alice")
    expect(captured_messages.first[:content]).to include("Summarize mode is active.")
    expect(captured_messages.first[:content]).to include("Topic: billing")
  end

  it "falls back to base prompt when method prompt file is missing" do
    configured_agent = described_class.with(user: "Bob")
    captured_messages = nil

    allow(configured_agent).to receive(:available_tools).and_return([])
    allow(configured_agent.provider).to receive(:chat) do |messages:, tools: [], **_options|
      captured_messages = messages
      OmniAgent::Providers::Response.new(content: "ok", raw_response: {}, tool_calls: [])
    end

    response = configured_agent.classify("Classify this")

    expect(response).to eq("ok")
    expect(configured_agent.last_entrypoint).to eq(:classify)
    expect(captured_messages.first[:content]).to include("You are AliasAgent.")
    expect(captured_messages.first[:content]).to include("Current user: Bob")
    expect(captured_messages.first[:content]).not_to include("Summarize mode is active.")
  end

  it "keeps original no-arg method behavior" do
    expect(agent.summarize).to eq("legacy summarize behavior")
    expect(agent.classify).to eq("legacy classify behavior")
  end
end
