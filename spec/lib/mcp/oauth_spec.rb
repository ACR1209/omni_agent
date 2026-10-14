require_relative "mcp_spec_helper"
require "jwt"
require "openssl"
require "webmock/rspec"

RSpec.describe OmniAgent::MCP::OAuth do
  let(:resource) { "https://app.example/mcp/support" }
  let(:issuer) { "https://auth.example" }
  let(:now) { Time.now.to_i }
  let(:valid_claims) do
    { "iss" => issuer, "aud" => resource, "sub" => "user-1", "exp" => now + 300, "scope" => "mcp:tools mcp:read" }
  end

  def request_with(authorization = nil)
    env = Rack::MockRequest.env_for("/", method: "POST")
    env["HTTP_AUTHORIZATION"] = authorization if authorization
    OmniAgent::MCP::Request.new(env)
  end

  describe OmniAgent::MCP::OAuth::AccessToken do
    it "reads space-separated scope claims" do
      expect(described_class.new("t", "scope" => "a b").scopes).to eq(%w[a b])
    end

    it "reads scp claims given as an array" do
      expect(described_class.new("t", scp: %w[a b]).scopes).to eq(%w[a b])
    end

    it "checks several scopes at once" do
      token = described_class.new("t", "scope" => "a b")

      expect(token.scope?("a", "b")).to be(true)
      expect(token.scope?(%w[a c])).to be(false)
    end

    it "exposes standard claims" do
      token = described_class.new("t", "sub" => "u", "azp" => "client", "aud" => "x", "exp" => 100)

      expect([ token.subject, token.client_id, token.audience, token.expires_at ]).to eq([ "u", "client", [ "x" ], Time.at(100) ])
    end

    it "does not include the raw token in #inspect" do
      expect(described_class.new("super-secret", "sub" => "u").inspect).not_to include("super-secret")
    end
  end

  describe OmniAgent::MCP::OAuth::ResourceServer do
    let(:claims_by_token) { { "good" => valid_claims } }
    let(:options) do
      {
        resource: resource,
        authorization_servers: issuer,
        scopes: %w[mcp:tools],
        verify_token: ->(token, _request) { claims_by_token[token] }
      }
    end

    def authenticate(authorization, **overrides, &block)
      described_class.new(**options, **overrides, &block).authenticate(request_with(authorization))
    end

    context "configuration" do
      it "requires exactly one verification method" do
        expect { described_class.new(**options.except(:verify_token)) }
          .to raise_error(ArgumentError, /exactly one of jwks_uri:, introspection: or verify_token:/)
        expect { described_class.new(**options, introspection: { url: "https://auth.example/introspect" }) }
          .to raise_error(ArgumentError, /exactly one/)
      end

      it "requires resource and authorization_servers" do
        expect { described_class.new(**options, resource: nil) }.to raise_error(ArgumentError, /requires resource:/)
        expect { described_class.new(**options, authorization_servers: []) }
          .to raise_error(ArgumentError, /requires authorization_servers:/)
      end

      it "rejects a resource that is not an absolute http(s) URL" do
        expect { described_class.new(**options, resource: "/mcp/support") }.to raise_error(ArgumentError, /absolute http\(s\) URL/)
        expect { described_class.new(**options, resource: "https://app.example/mcp#frag") }.to raise_error(ArgumentError)
      end

      it "accepts callables for resource and authorization_servers" do
        server = described_class.new(**options, resource: -> { resource }, authorization_servers: -> { [ issuer ] })

        expect(server.metadata).to include(resource: resource, authorization_servers: [ issuer ])
      end
    end

    it "fails without an error code when no token is sent" do
      result = authenticate(nil)

      expect(result.authenticated?).to be(false)
      expect(result.error).to be_nil
    end

    it "returns the access token as the principal by default" do
      result = authenticate("Bearer good")

      expect(result.authenticated?).to be(true)
      expect(result.principal).to be_a(OmniAgent::MCP::OAuth::AccessToken)
      expect(result.principal.subject).to eq("user-1")
      expect(result.access_token).to equal(result.principal)
    end

    it "maps the access token to a principal with the block" do
      result = authenticate("Bearer good") { |access_token, request| "#{access_token.subject}:#{request.class.name.demodulize}" }

      expect(result.principal).to eq("user-1:Request")
      expect(result.access_token.subject).to eq("user-1")
    end

    it "rejects the token when the block returns nil" do
      expect(authenticate("Bearer good") { nil }.error).to eq(:invalid_token)
    end

    it "accepts verify_token lambdas that only take the token" do
      result = authenticate("Bearer good", verify_token: ->(token) { claims_by_token[token] })

      expect(result.authenticated?).to be(true)
    end

    it "rejects tokens the verifier does not recognize" do
      expect(authenticate("Bearer unknown").error).to eq(:invalid_token)
    end

    it "rejects tokens issued for another resource" do
      claims_by_token["good"] = valid_claims.merge("aud" => "https://other.example/mcp")

      expect(authenticate("Bearer good").error).to eq(:invalid_token)
    end

    it "rejects tokens without an audience" do
      claims_by_token["good"] = valid_claims.except("aud")

      expect(authenticate("Bearer good").error).to eq(:invalid_token)
    end

    it "matches the audience regardless of a trailing slash or array form" do
      claims_by_token["good"] = valid_claims.merge("aud" => [ "https://other.example", "#{resource}/" ])

      expect(authenticate("Bearer good").authenticated?).to be(true)
    end

    it "uses audience: instead of the resource when given" do
      claims_by_token["good"] = valid_claims.merge("aud" => "api://support")

      expect(authenticate("Bearer good", audience: "api://support").authenticated?).to be(true)
      expect(authenticate("Bearer good").authenticated?).to be(false)
    end

    it "rejects expired tokens" do
      claims_by_token["good"] = valid_claims.merge("exp" => now - 120)

      expect(authenticate("Bearer good").error).to eq(:invalid_token)
    end

    it "tolerates small clock skew" do
      claims_by_token["good"] = valid_claims.merge("exp" => now - 5, "nbf" => now + 5)

      expect(authenticate("Bearer good").authenticated?).to be(true)
    end

    it "rejects tokens that are not valid yet" do
      claims_by_token["good"] = valid_claims.merge("nbf" => now + 600)

      expect(authenticate("Bearer good").error).to eq(:invalid_token)
    end

    it "rejects tokens from an untrusted issuer" do
      claims_by_token["good"] = valid_claims.merge("iss" => "https://evil.example")

      expect(authenticate("Bearer good").error).to eq(:invalid_token)
    end

    it "reports missing scopes as insufficient_scope" do
      claims_by_token["good"] = valid_claims.merge("scope" => "mcp:read")

      expect(authenticate("Bearer good").error).to eq(:insufficient_scope)
    end

    it "rejects the request when the authorization server cannot be reached" do
      failing = ->(_token) { raise OmniAgent::MCP::OAuth::VerificationError, "down" }

      expect(authenticate("Bearer good", verify_token: failing).error).to eq(:invalid_token)
    end

    it "builds RFC 9728 metadata" do
      server = described_class.new(**options, scopes_supported: %w[mcp:tools mcp:admin])

      expect(server.metadata(resource_name: "support")).to eq(
        resource: resource,
        authorization_servers: [ issuer ],
        scopes_supported: %w[mcp:tools mcp:admin],
        bearer_methods_supported: [ "header" ],
        resource_name: "support"
      )
    end

    it "builds the WWW-Authenticate challenge" do
      server = described_class.new(**options)

      expect(server.challenge(realm: "support", error: :insufficient_scope)).to eq(
        'Bearer realm="support", resource_metadata="https://app.example/mcp/support/.well-known/oauth-protected-resource", ' \
        'error="insufficient_scope", scope="mcp:tools"'
      )
    end
  end

  describe OmniAgent::MCP::OAuth::JWTVerifier do
    let(:key) { OpenSSL::PKey::RSA.generate(2048) }
    let(:jwks) { { "keys" => [ JWT::JWK.new(key, kid: "k1").export.transform_keys(&:to_s) ] } }
    let(:verifier) { described_class.new("https://auth.example/jwks.json") }

    before { allow(OmniAgent::MCP::OAuth::HTTPClient).to receive(:get_json).and_return(jwks) }

    def sign(payload, signing_key = key, algorithm = "RS256", kid: "k1")
      JWT.encode(payload, signing_key, algorithm, { kid: kid })
    end

    it "returns the payload of a valid token" do
      expect(verifier.call(sign(valid_claims))).to include("sub" => "user-1")
    end

    it "caches the key set" do
      2.times { verifier.call(sign(valid_claims)) }

      expect(OmniAgent::MCP::OAuth::HTTPClient).to have_received(:get_json).once
    end

    it "rejects tokens signed with another key" do
      expect(verifier.call(sign(valid_claims, OpenSSL::PKey::RSA.generate(2048)))).to be_nil
    end

    it "rejects symmetric algorithms" do
      expect(verifier.call(sign(valid_claims, "shared-secret", "HS256"))).to be_nil
    end

    it "requires exp and iss" do
      expect(verifier.call(sign(valid_claims.except("exp")))).to be_nil
      expect(verifier.call(sign(valid_claims.except("iss")))).to be_nil
    end

    it "rejects expired tokens" do
      expect(verifier.call(sign(valid_claims.merge("exp" => now - 600)))).to be_nil
    end

    it "does not refetch the key set on every unknown kid" do
      3.times { verifier.call(sign(valid_claims, kid: "unknown")) }

      expect(OmniAgent::MCP::OAuth::HTTPClient).to have_received(:get_json).once
    end

    it "rejects garbage" do
      expect(verifier.call("not-a-jwt")).to be_nil
    end
  end

  describe OmniAgent::MCP::OAuth::IntrospectionVerifier do
    let(:verifier) do
      described_class.new(url: "https://auth.example/introspect", client_id: "mcp server", client_secret: -> { "s&cret" })
    end

    it "returns the response for active tokens" do
      allow(OmniAgent::MCP::OAuth::HTTPClient).to receive(:post_form_json).and_return(valid_claims.merge("active" => true))

      expect(verifier.call("token")).to include("sub" => "user-1")
      expect(OmniAgent::MCP::OAuth::HTTPClient).to have_received(:post_form_json).with(
        "https://auth.example/introspect",
        { "token" => "token", "token_type_hint" => "access_token" },
        basic_auth: [ "mcp+server", "s%26cret" ]
      )
    end

    it "returns nil for inactive tokens" do
      allow(OmniAgent::MCP::OAuth::HTTPClient).to receive(:post_form_json).and_return("active" => false)

      expect(verifier.call("token")).to be_nil
    end

    it "does not include the client secret in #inspect" do
      expect(described_class.new(url: "https://x", client_secret: "hidden").inspect).not_to include("hidden")
    end
  end

  describe OmniAgent::MCP::OAuth::HTTPClient do
    it "parses JSON responses" do
      stub_request(:get, "https://auth.example/jwks.json").to_return(body: '{"keys":[]}')

      expect(described_class.get_json("https://auth.example/jwks.json")).to eq("keys" => [])
    end

    it "sends form posts with basic auth" do
      stub = stub_request(:post, "https://auth.example/introspect")
        .with(basic_auth: %w[id secret], body: { "token" => "t" })
        .to_return(body: '{"active":true}')

      expect(described_class.post_form_json("https://auth.example/introspect", { "token" => "t" }, basic_auth: %w[id secret]))
        .to eq("active" => true)
      expect(stub).to have_been_requested
    end

    it "raises VerificationError on HTTP errors" do
      stub_request(:get, "https://auth.example/jwks.json").to_return(status: 500)

      expect { described_class.get_json("https://auth.example/jwks.json") }
        .to raise_error(OmniAgent::MCP::OAuth::VerificationError, /HTTP 500/)
    end

    it "raises VerificationError on network errors" do
      stub_request(:get, "https://auth.example/jwks.json").to_timeout

      expect { described_class.get_json("https://auth.example/jwks.json") }
        .to raise_error(OmniAgent::MCP::OAuth::VerificationError)
    end
  end
end
