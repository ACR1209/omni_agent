require_relative "mcp_spec_helper"

RSpec.describe OmniAgent::MCP::Handler do
  let(:server_class) do
    klass = Class.new(OmniAgent::MCP::Server) do
      instructions "Spec instructions."
      tools MCPSpecTools::Echo, MCPSpecTools::Whoami, MCPSpecTools::Boom, MCPSpecTools::Admin
      authorize_tool { |tool_class, principal| principal == :admin || !tool_class.tags.include?(:admin) }
      context { |principal, _request| { current_user: "user-#{principal}" } }
    end
    stub_const("HandlerSpecServer", klass)
  end
  let(:principal) { :guest }
  let(:handler) { described_class.new(server_class.new(principal: principal)) }

  def request(method, params = nil, id: 1)
    message = { "jsonrpc" => "2.0", "id" => id, "method" => method }
    message["params"] = params if params
    handler.call(message)
  end

  describe "initialize" do
    it "echoes a supported protocol version" do
      response = request("initialize", { "protocolVersion" => "2025-06-18", "capabilities" => {} })

      expect(response[:result]).to eq(
        protocolVersion: "2025-06-18",
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "handler_spec", version: "0.1.0" },
        instructions: "Spec instructions."
      )
    end

    it "answers with the latest version when the requested one is unsupported" do
      response = request("initialize", { "protocolVersion" => "1999-01-01" })

      expect(response[:result][:protocolVersion]).to eq(OmniAgent::MCP::LATEST_PROTOCOL_VERSION)
    end
  end

  it "answers ping with an empty result" do
    expect(request("ping", id: "abc")).to eq(jsonrpc: "2.0", id: "abc", result: {})
  end

  it "lists only the tools visible to the principal" do
    names = request("tools/list")[:result][:tools].map { |tool| tool[:name] }

    expect(names).to eq(%w[Echo Whoami Boom])
  end

  describe "tools/call" do
    it "invokes the tool and returns text content" do
      response = request("tools/call", { "name" => "Echo", "arguments" => { "text" => "hey" } })

      expect(response[:result]).to eq(content: [ { type: "text", text: "echo: hey" } ])
    end

    it "passes principal and context block values into the tool context" do
      response = request("tools/call", { "name" => "Whoami" })

      expect(response[:result][:structuredContent]).to eq("principal" => "guest", "current_user" => "user-guest")
    end

    it "reports validation failures as tool errors" do
      response = request("tools/call", { "name" => "Echo", "arguments" => { "text" => "way too long text" } })

      expect(response[:result][:isError]).to be(true)
      expect(response[:result][:content].first[:text]).to eq("Error executing tool: text must be at most 10 characters")
    end

    it "reports missing arguments as tool errors" do
      response = request("tools/call", { "name" => "Echo" })

      expect(response[:result][:isError]).to be(true)
      expect(response[:result][:content].first[:text]).to include("missing required argument(s): text")
    end

    it "reports exceptions raised by the tool as tool errors" do
      response = request("tools/call", { "name" => "Boom" })

      expect(response[:result]).to eq(content: [ { type: "text", text: "Error executing tool: kaboom" } ], isError: true)
    end

    it "rejects unknown tools with -32602" do
      response = request("tools/call", { "name" => "Nope" })

      expect(response[:error]).to eq(code: -32_602, message: "Unknown tool: Nope")
    end

    it "treats unauthorized tools as unknown" do
      response = request("tools/call", { "name" => "Admin" })

      expect(response[:error]).to eq(code: -32_602, message: "Unknown tool: Admin")
    end

    it "rejects non-object arguments with -32602" do
      response = request("tools/call", { "name" => "Echo", "arguments" => [ 1 ] })

      expect(response[:error][:code]).to eq(-32_602)
    end

    context "as admin" do
      let(:principal) { :admin }

      it "can call admin tools" do
        expect(request("tools/call", { "name" => "Admin" })[:result][:content].first[:text]).to eq("admin")
      end
    end
  end

  it "returns -32601 for unknown methods" do
    expect(request("resources/list")[:error]).to eq(code: -32_601, message: "Method not found: resources/list")
  end

  it "returns -32602 when params is not an object" do
    expect(handler.call("jsonrpc" => "2.0", "id" => 1, "method" => "ping", "params" => [])[:error][:code]).to eq(-32_602)
  end

  it "returns nil for notifications" do
    expect(handler.call("jsonrpc" => "2.0", "method" => "notifications/initialized")).to be_nil
  end

  it "returns nil for client responses" do
    expect(handler.call("jsonrpc" => "2.0", "id" => 3, "result" => {})).to be_nil
  end

  it "rejects messages without jsonrpc 2.0" do
    expect(handler.call("id" => 1, "method" => "ping")).to eq(jsonrpc: "2.0", id: 1, error: { code: -32_600, message: "Invalid Request" })
  end

  it "rejects batches" do
    expect(handler.call([ { "jsonrpc" => "2.0", "id" => 1, "method" => "ping" } ])[:error][:code]).to eq(-32_600)
  end

  it "accepts symbol keys" do
    expect(handler.call(jsonrpc: "2.0", id: 1, method: "ping")[:result]).to eq({})
  end

  it "returns -32603 for unexpected internal errors" do
    allow(server_class).to receive(:tool_registry).and_raise(OmniAgent::MCPError, "broken")

    expect(request("tools/list")[:error]).to eq(code: -32_603, message: "Internal error")
  end
end
