require_relative "mcp_spec_helper"

RSpec.describe OmniAgent::MCP::ToolAdapter do
  describe ".definition" do
    it "builds the MCP tool definition with title and annotations" do
      definition = described_class.definition("echo", MCPSpecTools::Echo)

      expect(definition).to eq(
        name: "echo",
        title: "Echo",
        description: "Echoes text back.",
        inputSchema: MCPSpecTools::Echo.json_schema,
        annotations: { readOnlyHint: true, idempotentHint: true }
      )
    end

    it "omits title and annotations when the tool declares neither" do
      definition = described_class.definition("Boom", MCPSpecTools::Boom)

      expect(definition.keys).to eq(%i[name description inputSchema])
    end
  end

  describe ".result" do
    it "wraps strings as text content" do
      expect(described_class.result("hi")).to eq(content: [ { type: "text", text: "hi" } ])
    end

    it "maps nil to empty text" do
      expect(described_class.result(nil)).to eq(content: [ { type: "text", text: "" } ])
    end

    it "serializes hashes as JSON text plus structuredContent" do
      result = described_class.result({ temp: 16, city: "Quito" })

      expect(result[:content]).to eq([ { type: "text", text: '{"temp":16,"city":"Quito"}' } ])
      expect(result[:structuredContent]).to eq("temp" => 16, "city" => "Quito")
    end

    it "serializes arrays as JSON text" do
      expect(described_class.result([ 1, 2 ])).to eq(content: [ { type: "text", text: "[1,2]" } ])
    end

    it "stringifies other values" do
      expect(described_class.result(42)).to eq(content: [ { type: "text", text: "42" } ])
    end
  end

  describe ".error_result" do
    it "flags the result as an error" do
      expect(described_class.error_result("bad")).to eq(content: [ { type: "text", text: "bad" } ], isError: true)
    end
  end
end
