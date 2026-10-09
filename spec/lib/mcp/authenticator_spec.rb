require_relative "mcp_spec_helper"

RSpec.describe OmniAgent::MCP::Authenticator do
  def build_server(&block)
    klass = Class.new(OmniAgent::MCP::Server)
    stub_const("AuthSpecServer", klass)
    klass.class_eval(&block) if block
    klass
  end

  def request_with(authorization = nil)
    env = Rack::MockRequest.env_for("/", method: "POST")
    env["HTTP_AUTHORIZATION"] = authorization if authorization
    OmniAgent::MCP::Request.new(env)
  end

  def authenticate(server, authorization = nil)
    described_class.new(server).authenticate(request_with(authorization))
  end

  context "with an array of bearer tokens" do
    let(:server) { build_server { authenticate :bearer, tokens: %w[alpha beta] } }

    it "accepts any configured token" do
      result = authenticate(server, "Bearer beta")

      expect(result).to be_authenticated
      expect(result.principal).to eq(:bearer_token)
    end

    it "rejects a wrong token" do
      expect(authenticate(server, "Bearer gamma")).not_to be_authenticated
    end

    it "rejects a missing header" do
      expect(authenticate(server)).not_to be_authenticated
    end

    it "rejects non-bearer schemes" do
      expect(authenticate(server, "Basic alpha")).not_to be_authenticated
    end
  end

  it "uses hash keys as principals for named tokens" do
    server = build_server { authenticate :bearer, tokens: { "ci" => "ci-token", "ops" => "ops-token" } }

    expect(authenticate(server, "Bearer ops-token").principal).to eq("ops")
  end

  it "evaluates token procs per request" do
    tokens = %w[first]
    server = build_server { authenticate :bearer, tokens: -> { tokens } }

    expect(authenticate(server, "Bearer first")).to be_authenticated
    tokens.replace(%w[second])
    expect(authenticate(server, "Bearer first")).not_to be_authenticated
    expect(authenticate(server, "Bearer second")).to be_authenticated
  end

  it "ignores blank configured tokens" do
    server = build_server { authenticate :bearer, tokens: -> { "".split(",") + [ "" ] } }

    expect(authenticate(server, "Bearer  ")).not_to be_authenticated
  end

  it "uses the custom block result as principal" do
    server = build_server { authenticate { |request| request.bearer_token == "u1" ? { id: 1 } : nil } }

    expect(authenticate(server, "Bearer u1").principal).to eq(id: 1)
    expect(authenticate(server, "Bearer u2")).not_to be_authenticated
  end

  it "allows everything with :none" do
    result = authenticate(build_server { authenticate :none })

    expect(result).to be_authenticated
    expect(result.principal).to be_nil
  end

  it "raises when the server declares no authentication" do
    expect { authenticate(build_server) }.to raise_error(OmniAgent::MCPError, /authenticate :none/)
  end
end
