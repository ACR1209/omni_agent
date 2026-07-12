require_relative "../../spec_helper"
require_relative "../../../lib/omni_agent/streaming/event"
require_relative "../../../lib/omni_agent/providers/response"

RSpec.describe OmniAgent::Streaming::Event do
  it "builds a text event" do
    event = described_class.text("Hi")

    expect(event.type).to eq(:text)
    expect(event.text).to eq("Hi")
    expect(event.text?).to be(true)
    expect(event.tool_call?).to be(false)
    expect(event.tool_result?).to be(false)
    expect(event.done?).to be(false)
  end

  it "builds a tool_call event" do
    event = described_class.tool_call(name: "SearchTool", arguments: { query: "hi" }, id: "call_1")

    expect(event.type).to eq(:tool_call)
    expect(event.tool_call?).to be(true)
    expect(event.tool_name).to eq("SearchTool")
    expect(event.tool_arguments).to eq(query: "hi")
    expect(event.tool_id).to eq("call_1")
  end

  it "builds a tool_result event, defaulting error to false" do
    event = described_class.tool_result(name: "SearchTool", id: "call_1", content: "result")

    expect(event.type).to eq(:tool_result)
    expect(event.tool_result?).to be(true)
    expect(event.content).to eq("result")
    expect(event.error?).to be(false)
  end

  it "builds an errored tool_result event" do
    event = described_class.tool_result(name: "SearchTool", id: "call_1", content: "boom", error: true)

    expect(event.error?).to be(true)
  end

  it "builds a done event carrying the final response" do
    response = OmniAgent::Providers::Response.new(content: "ok", raw_response: {}, tool_calls: [])
    event = described_class.done(response)

    expect(event.type).to eq(:done)
    expect(event.done?).to be(true)
    expect(event.response).to eq(response)
  end
end
