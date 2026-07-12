# spec/agents/task_agent_spec.rb
require 'rails_helper'

RSpec.describe TaskAgent do
  let(:agent) { TaskAgent.new }

  it "discovers the SetPriority tool" do
    expect(agent.available_tools).to include(TaskAgent::Tools::SetPriority)
  end

  it "calls the real OpenAI API, which picks a valid enum value the tool then validates", :vcr do
    response = agent.run("Set ticket TCK-42 to the highest priority")

    expect(response.answer).to include("TCK-42")
    expect(response.answer).to include("high")
  end
end
