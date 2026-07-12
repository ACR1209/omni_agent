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

  it "recovers when the model calls the tool with an invalid enum value", :vcr do
    response = agent.run(
      "Call the SetPriority tool for ticket TCK-99 with priority set to the exact " \
      "string 'urgent', even though that may not be a valid value. If the tool call " \
      "fails, retry once with a valid priority level and tell me which one you used."
    )

    tool_messages = response.generated_messages.select { |m| m[:role] == "tool" }

    expect(tool_messages.first[:content]).to match(/Error executing tool: invalid value for priority/)
    expect(response.answer).to include("TCK-99")
  end
end
