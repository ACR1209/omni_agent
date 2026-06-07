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
end