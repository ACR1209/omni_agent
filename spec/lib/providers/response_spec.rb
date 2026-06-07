require_relative "../../spec_helper"
require_relative "../../../lib/omni_agent/providers/response"

RSpec.describe OmniAgent::Providers::Response do
  describe "#initialize" do
    it "sets content, tool_calls, and raw_response" do
      response = described_class.new(
        content: "hi",
        tool_calls: [{ name: "search" }],
        raw_response: { "id" => "123" }
      )

      expect(response.content).to eq("hi")
      expect(response.tool_calls).to eq([{ name: "search" }])
      expect(response.raw_response).to eq({ "id" => "123" })
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
      response = described_class.new(content: "hi", tool_calls: [{ name: "search" }])

      expect(response.tool_calls?).to be(true)
    end
  end
end
