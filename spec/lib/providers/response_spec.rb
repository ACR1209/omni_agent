require_relative "../../spec_helper"
require_relative "../../../lib/omni_agent/providers/response"

RSpec.describe OmniAgent::Providers::Response do
  describe "#initialize" do
    it "sets content, tool_calls, raw_response, raw_request, and generated_messages" do
      response = described_class.new(
        content: "hi",
        tool_calls: [ { name: "search" } ],
        raw_response: { "id" => "123" },
        raw_request: { model: "gpt-test" },
        generated_messages: [ { role: "assistant", content: "hi" } ]
      )

      expect(response.content).to eq("hi")
      expect(response.tool_calls).to eq([ { name: "search" } ])
      expect(response.raw_response).to eq({ "id" => "123" })
      expect(response.raw_request).to eq({ model: "gpt-test" })
      expect(response.generated_messages).to eq([ { role: "assistant", content: "hi" } ])
    end

    it "normalizes nil tool_calls into an empty array" do
      response = described_class.new(content: "hi", tool_calls: nil)

      expect(response.tool_calls).to eq([])
    end
  end

  describe "#tool_calls?" do
    it "returns false when no tool calls are present" do
      response = described_class.new(content: "hi")

      expect(response.tool_calls?).to be(false)
    end

    it "returns true when tool calls are present" do
      response = described_class.new(content: "hi", tool_calls: [ { name: "search" } ])

      expect(response.tool_calls?).to be(true)
    end
  end

  describe "#answer" do
    it "returns the content" do
      response = described_class.new(content: "hello")

      expect(response.answer).to eq("hello")
    end
  end

  describe "#with_generated_messages" do
    it "updates generated_messages and returns self" do
      response = described_class.new(content: "hello")

      returned = response.with_generated_messages([ { role: "assistant", content: "hello" } ])

      expect(returned).to equal(response)
      expect(response.generated_messages).to eq([ { role: "assistant", content: "hello" } ])
    end
  end
end
