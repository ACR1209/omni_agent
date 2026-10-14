require_relative "mcp_spec_helper"

RSpec.describe OmniAgent::MCP::RackApp do
  around do |example|
    previous_config = OmniAgent.instance_variable_get(:@configuration)
    OmniAgent.instance_variable_set(:@configuration, nil)
    example.run
    OmniAgent.instance_variable_set(:@configuration, previous_config)
  end

  let(:server_class) do
    klass = Class.new(OmniAgent::MCP::Server) do
      tools MCPSpecTools::Echo
      authenticate :bearer, tokens: %w[secret]
      allowed_origins "https://allowed.example"
    end
    stub_const("RackSpecServer", klass)
  end
  let(:app) { described_class.new(server_class) }
  let(:mock) { Rack::MockRequest.new(app) }
  let(:auth) { { "HTTP_AUTHORIZATION" => "Bearer secret", "CONTENT_TYPE" => "application/json" } }

  def post(body, headers = auth)
    mock.post("/", headers.merge(input: body.is_a?(String) ? body : JSON.generate(body)))
  end

  let(:list_request) { { jsonrpc: "2.0", id: 1, method: "tools/list" } }

  it "answers requests with 200 JSON" do
    response = post(list_request)

    expect(response.status).to eq(200)
    expect(response.headers["content-type"]).to eq("application/json")
    expect(JSON.parse(response.body).dig("result", "tools", 0, "name")).to eq("Echo")
  end

  it "accepts the server class name as a string" do
    server_class
    response = Rack::MockRequest.new(described_class.new("RackSpecServer")).post("/", auth.merge(input: JSON.generate(list_request)))

    expect(response.status).to eq(200)
  end

  it "returns 202 with no body for notifications" do
    response = post({ jsonrpc: "2.0", method: "notifications/initialized" })

    expect(response.status).to eq(202)
    expect(response.body).to eq("")
  end

  it "returns 401 with WWW-Authenticate when the token is missing" do
    response = post(list_request, { "CONTENT_TYPE" => "application/json" })

    expect(response.status).to eq(401)
    expect(response.headers["www-authenticate"]).to eq('Bearer realm="rack_spec"')
  end

  it "returns 401 for a wrong token" do
    expect(post(list_request, { "HTTP_AUTHORIZATION" => "Bearer nope" }).status).to eq(401)
  end

  it "returns 403 for disallowed origins" do
    expect(post(list_request, auth.merge("HTTP_ORIGIN" => "https://evil.example")).status).to eq(403)
  end

  it "allows origins from the server allowlist" do
    expect(post(list_request, auth.merge("HTTP_ORIGIN" => "https://allowed.example")).status).to eq(200)
  end

  it "allows origins from the global configuration" do
    OmniAgent.configuration.mcp_allowed_origins = [ %r{\Ahttps://.*\.global\.example\z} ]

    expect(post(list_request, auth.merge("HTTP_ORIGIN" => "https://app.global.example")).status).to eq(200)
  end

  it "returns 405 for GET" do
    response = mock.get("/", auth)

    expect(response.status).to eq(405)
    expect(response.headers["allow"]).to eq("POST")
  end

  it "returns 405 for DELETE" do
    expect(mock.delete("/", auth).status).to eq(405)
  end

  it "returns 400 for an unsupported MCP-Protocol-Version header" do
    expect(post(list_request, auth.merge("HTTP_MCP_PROTOCOL_VERSION" => "1999-01-01")).status).to eq(400)
  end

  it "accepts a supported MCP-Protocol-Version header" do
    expect(post(list_request, auth.merge("HTTP_MCP_PROTOCOL_VERSION" => "2025-06-18")).status).to eq(200)
  end

  it "returns 413 when the body is too large" do
    OmniAgent.configuration.mcp_max_request_bytes = 10

    expect(post(list_request).status).to eq(413)
  end

  it "returns 400 with a parse error for invalid JSON" do
    response = post("{not json")

    expect(response.status).to eq(400)
    expect(JSON.parse(response.body).dig("error", "code")).to eq(-32_700)
  end

  it "returns 400 for invalid JSON-RPC messages" do
    response = post([ list_request ])

    expect(response.status).to eq(400)
    expect(JSON.parse(response.body).dig("error", "code")).to eq(-32_600)
  end

  it "raises when the server does not declare authentication" do
    stub_const("OpenSpecServer", Class.new(OmniAgent::MCP::Server))

    expect { Rack::MockRequest.new(described_class.new("OpenSpecServer")).post("/", input: "{}") }
      .to raise_error(OmniAgent::MCPError, /does not declare authentication/)
  end

  it "does not serve OAuth metadata for servers that do not use OAuth" do
    expect(mock.get("/.well-known/oauth-protected-resource").status).to eq(401)
  end

  context "with OAuth" do
    let(:resource) { "https://app.example/mcp/rack-oauth" }
    let(:claims) do
      {
        "full" => { "iss" => "https://auth.example", "aud" => resource, "sub" => "user-1", "scope" => "mcp:tools" },
        "read_only" => { "iss" => "https://auth.example", "aud" => resource, "sub" => "user-2", "scope" => "mcp:read" }
      }
    end
    let(:server_class) do
      token_claims = claims
      klass = Class.new(OmniAgent::MCP::Server) do
        tools MCPSpecTools::Whoami
        authenticate :oauth,
                     resource: "https://app.example/mcp/rack-oauth",
                     authorization_servers: [ "https://auth.example" ],
                     scopes: %w[mcp:tools],
                     verify_token: ->(token) { token_claims[token] }
        context { |_principal, _request| { scopes: access_token.scopes.join(",") } }
      end
      stub_const("RackOauthSpecServer", klass)
    end
    let(:metadata_url) { "#{resource}/.well-known/oauth-protected-resource" }
    let(:call_request) { { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "Whoami", arguments: {} } } }

    it "serves Protected Resource Metadata without authentication" do
      response = mock.get("/.well-known/oauth-protected-resource", "HTTP_ORIGIN" => "https://inspector.example")

      expect(response.status).to eq(200)
      expect(response.headers["access-control-allow-origin"]).to eq("*")
      expect(JSON.parse(response.body)).to eq(
        "resource" => resource,
        "authorization_servers" => [ "https://auth.example" ],
        "scopes_supported" => [ "mcp:tools" ],
        "bearer_methods_supported" => [ "header" ],
        "resource_name" => "rack_oauth_spec"
      )
    end

    it "answers CORS preflight for the metadata" do
      response = mock.request("OPTIONS", "/.well-known/oauth-protected-resource")

      expect(response.status).to eq(204)
      expect(response.headers["access-control-allow-headers"]).to include("mcp-protocol-version")
    end

    it "only allows GET for the metadata" do
      expect(mock.post("/.well-known/oauth-protected-resource").status).to eq(405)
    end

    it "points clients to the metadata when the token is missing" do
      response = post(list_request, { "CONTENT_TYPE" => "application/json" })

      expect(response.status).to eq(401)
      expect(response.headers["www-authenticate"])
        .to eq(%(Bearer realm="rack_oauth_spec", resource_metadata="#{metadata_url}", scope="mcp:tools"))
    end

    it "returns 401 invalid_token for unknown tokens" do
      response = post(list_request, { "HTTP_AUTHORIZATION" => "Bearer nope" })

      expect(response.status).to eq(401)
      expect(response.headers["www-authenticate"]).to include('error="invalid_token"')
    end

    it "returns 403 insufficient_scope when a required scope is missing" do
      response = post(list_request, { "HTTP_AUTHORIZATION" => "Bearer read_only" })

      expect(response.status).to eq(403)
      expect(response.headers["www-authenticate"]).to include('error="insufficient_scope"', 'scope="mcp:tools"')
    end

    it "runs tools with the access token as principal and in the context" do
      response = post(call_request, { "HTTP_AUTHORIZATION" => "Bearer full" })
      content = JSON.parse(JSON.parse(response.body).dig("result", "content", 0, "text"))

      expect(response.status).to eq(200)
      expect(content).to include("principal" => "user-1")
    end

    it "exposes the access token to the server instance" do
      server = server_class.new(access_token: OmniAgent::MCP::OAuth::AccessToken.new("t", claims["full"]))

      expect(server.tool_context).to include(scopes: "mcp:tools", mcp_access_token: server.access_token)
    end
  end

  it "rejects classes that are not MCP servers" do
    expect { Rack::MockRequest.new(described_class.new("String")).post("/", input: "{}") }
      .to raise_error(OmniAgent::MCPError, /not an OmniAgent::MCP::Server subclass/)
  end
end
