require "rails_helper"

RSpec.describe ResearchServer do
  around do |example|
    previous = ENV["RESEARCH_MCP_TOKENS"]
    ENV["RESEARCH_MCP_TOKENS"] = "secret,other"
    example.run
    ENV["RESEARCH_MCP_TOKENS"] = previous
  end

  let(:app) { OmniAgent::MCP::RackApp.new("ResearchServer") }

  def rpc(method, params = nil, token: "secret")
    body = { jsonrpc: "2.0", id: 1, method: method }
    body[:params] = params if params
    headers = { "CONTENT_TYPE" => "application/json", input: JSON.generate(body) }
    headers["HTTP_AUTHORIZATION"] = "Bearer #{token}" if token
    Rack::MockRequest.new(app).post("/mcp/research", headers)
  end

  it "lists the dummy app tools with annotations" do
    tools = JSON.parse(rpc("tools/list").body).dig("result", "tools")

    expect(tools.map { |tool| tool["name"] }).to include("GetWeather", "SetPriority", "AssignTicket", "SetEstimate", "ask_alias_agent")
    weather = tools.find { |tool| tool["name"] == "GetWeather" }
    expect(weather["title"]).to eq("Get weather")
    expect(weather["annotations"]).to eq(
      "readOnlyHint" => true, "destructiveHint" => false, "idempotentHint" => true, "openWorldHint" => true
    )
  end

  it "auto-registers tools from app/mcp_servers/research_server/tools first" do
    names = JSON.parse(rpc("tools/list").body).dig("result", "tools").map { |tool| tool["name"] }

    expect(names.first).to eq("SupportedCities")
    expect(ResearchServer.namespace_tool_classes).to eq([ ResearchServer::Tools::SupportedCities ])
  end

  it "returns structured content from a server-local tool" do
    result = JSON.parse(rpc("tools/call", { name: "SupportedCities" }).body)["result"]

    expect(result["structuredContent"]).to eq("cities" => [ "Quito", "Guayaquil", "Cuenca" ])
  end

  it "calls a tool" do
    result = JSON.parse(rpc("tools/call", { name: "GetWeather", arguments: { city: "Quito" } }).body)["result"]

    expect(result["content"]).to eq([ { "type" => "text", "text" => "16°C and sunny in Quito" } ])
  end

  it "rejects requests without a valid token" do
    expect(rpc("tools/list", token: nil).status).to eq(401)
    expect(rpc("tools/list", token: "wrong").status).to eq(401)
  end

  it "runs an exposed agent and forwards the configured context" do
    forwarded_context = nil
    allow_any_instance_of(AliasAgent).to receive(:available_tools).and_return([])
    allow_any_instance_of(AliasAgent).to receive(:resolve_provider).and_return(OmniAgent::Providers::Mock.new)
    allow_any_instance_of(AliasAgent).to receive(:run).and_wrap_original do |original, input, context: {}, **rest|
      forwarded_context = context
      original.call(input, context: context, **rest)
    end

    result = JSON.parse(rpc("tools/call", { name: "ask_alias_agent", arguments: { input: "Hello?" } }).body)["result"]

    expect(result["content"].first["text"]).to eq(OmniAgent::Providers::Mock::LOREM_IPSUM)
    expect(forwarded_context).to eq(current_user: :bearer_token)
  end

  it "is mounted in the dummy app routes" do
    route = Rails.application.routes.routes.find { |r| r.path.spec.to_s.start_with?("/mcp/research") }

    expect(route.app.app).to be_a(OmniAgent::MCP::RackApp)
  end
end
