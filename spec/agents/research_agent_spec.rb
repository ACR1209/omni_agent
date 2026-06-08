# spec/agents/research_agent_spec.rb
require 'rails_helper'

RSpec.describe ResearchAgent do
  let(:agent) { ResearchAgent.new }
  let(:tool) { agent.available_tools.first }

  it "automatically discovers tools in its namespace" do
    tools = agent.available_tools
    expect(tools).to include(ResearchAgent::Tools::GetWeather)
  end

  it "executes the tool correctly" do
    # This verifies the logic flow from Agent -> Tool -> Execute
    result = tool.invoke(city: "Argentina")
    expect(result).to eq("Sunny in Argentina")
  end

  it "decides to call the weather tool when asked about Quito", :vcr do
    response = agent.run("What is the weather in Quito?")

    expect(response).to include("16°C")
  end

  it "logs before and after generation callbacks", :vcr do
    agent.run("What is the weather in Quito?")

    expect(agent.instance_variable_get(:@before_log)).to include("before_generation called")
    expect(agent.instance_variable_get(:@after_log)).to include("after_generation called")
  end

  it "has access to instance variables set in before_generation callbacks" do
    captured_messages = nil

    allow(agent.provider).to receive(:chat) do |messages:, tools: [], **_options|
      captured_messages = messages
      OmniAgent::Providers::Response.new(content: "ok", raw_response: {}, tool_calls: [])
    end

    agent.run("What is the weather in Quito?")

    expect(captured_messages.first[:role]).to eq("system")
    expect(captured_messages.first[:content]).to include("Current user: Test User")
  end
end