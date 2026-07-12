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

  it "recovers when the model calls SetEstimate with an out-of-range value", :vcr do
    response = agent.run(
      "Call the SetEstimate tool for ticket TCK-7 with hours set to the exact number " \
      "100, even though that may be out of range. If the tool call fails, retry once " \
      "with a valid number of hours and tell me which one you used."
    )

    tool_messages = response.generated_messages.select { |m| m[:role] == "tool" }

    expect(tool_messages.first[:content]).to match(/Error executing tool: hours must be <= 40/)
    expect(response.answer).to include("TCK-7")
  end

  it "resolves a polymorphic actor argument into a fetched record", :vcr do
    response = agent.run("Assign ticket TCK-5 to the User with id 42.")

    tool_messages = response.generated_messages.select { |m| m[:role] == "tool" }

    expect(tool_messages.first[:content]).to match(/Ticket TCK-5 assigned to User Bob \(#42\)/)
    expect(response.answer).to include("TCK-5")
  end
end
