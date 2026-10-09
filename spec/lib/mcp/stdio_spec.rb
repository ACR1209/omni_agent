require_relative "mcp_spec_helper"

RSpec.describe OmniAgent::MCP::Stdio do
  let(:server_class) do
    klass = Class.new(OmniAgent::MCP::Server) do
      tools MCPSpecTools::Echo, MCPSpecTools::Whoami, MCPSpecTools::Admin
      stdio_principal { :local_admin }
      authorize_tool { |tool_class, principal| principal == :local_admin || !tool_class.tags.include?(:admin) }
    end
    stub_const("StdioSpecServer", klass)
  end

  def run_lines(*lines)
    input = StringIO.new(lines.map { |line| "#{line}\n" }.join)
    output = StringIO.new
    described_class.new(server_class, input: input, output: output).run
    output.string.lines.map { |line| JSON.parse(line) }
  end

  it "handles a newline-delimited session" do
    responses = run_lines(
      JSON.generate(jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-11-25" }),
      JSON.generate(jsonrpc: "2.0", method: "notifications/initialized"),
      "",
      JSON.generate(jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "Echo", arguments: { text: "hi" } })
    )

    expect(responses.map { |response| response["id"] }).to eq([ 1, 2 ])
    expect(responses[0].dig("result", "serverInfo", "name")).to eq("stdio_spec")
    expect(responses[1].dig("result", "content", 0, "text")).to eq("echo: hi")
  end

  it "answers bad JSON lines with a parse error and keeps going" do
    responses = run_lines("{oops", JSON.generate(jsonrpc: "2.0", id: 5, method: "ping"))

    expect(responses[0]).to eq("jsonrpc" => "2.0", "id" => nil, "error" => { "code" => -32_700, "message" => "Parse error" })
    expect(responses[1]).to eq("jsonrpc" => "2.0", "id" => 5, "result" => {})
  end

  it "uses stdio_principal and still applies authorize_tool" do
    responses = run_lines(
      JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/list"),
      JSON.generate(jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "Whoami" })
    )

    expect(responses[0].dig("result", "tools").map { |tool| tool["name"] }).to eq(%w[Echo Whoami Admin])
    expect(responses[1].dig("result", "structuredContent", "principal")).to eq("local_admin")
  end

  it "does not require authentication to be declared" do
    expect(server_class.configured_authentication).to be_nil
    expect(run_lines(JSON.generate(jsonrpc: "2.0", id: 1, method: "ping")).first["result"]).to eq({})
  end
end
