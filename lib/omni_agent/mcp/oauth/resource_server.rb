require "uri"

module OmniAgent
  module MCP
    module OAuth
      # Built by `authenticate :oauth, ...`. Validates bearer access tokens
      # (signature or introspection, issuer, audience, expiry and scopes) and
      # describes the server in Protected Resource Metadata (RFC 9728) so MCP
      # clients can find the authorization server.
      class ResourceServer
        METADATA_PATH = "/.well-known/oauth-protected-resource".freeze
        # Seconds of clock skew tolerated when checking exp and nbf.
        LEEWAY = 30

        attr_reader :scopes

        def initialize(resource:, authorization_servers:, scopes: [], scopes_supported: nil, audience: nil,
                       jwks_uri: nil, algorithms: JWTVerifier::DEFAULT_ALGORITHMS, introspection: nil,
                       verify_token: nil, &principal_block)
          raise ArgumentError, "authenticate :oauth requires resource:" if resource.nil?
          raise ArgumentError, "authenticate :oauth requires authorization_servers:" if Array(authorization_servers).empty?

          validate_resource!(resource) unless resource.respond_to?(:call)

          @resource = resource
          @authorization_servers = authorization_servers
          @scopes = Array(scopes).map(&:to_s).freeze
          @scopes_supported = scopes_supported && Array(scopes_supported).map(&:to_s).freeze
          @audience = audience
          @principal_block = principal_block
          @verifier = build_verifier(jwks_uri, algorithms, introspection, verify_token)
        end

        # Returns an Authenticator::Result. `error` is nil when no token was
        # sent, :invalid_token or :insufficient_scope (RFC 6750 section 3.1).
        def authenticate(request)
          token = request.bearer_token
          return failure(nil) if token.nil?

          claims = verify(token, request)
          return failure(:invalid_token) unless claims.is_a?(Hash)

          access_token = AccessToken.new(token, claims)
          return failure(:invalid_token) unless valid?(access_token)
          return failure(:insufficient_scope) unless access_token.scope?(scopes)

          principal = @principal_block ? @principal_block.call(access_token, request) : access_token
          return failure(:invalid_token) unless principal

          Authenticator::Result.new(true, principal, nil, access_token)
        rescue VerificationError => e
          MCP.logger&.error("[OmniAgent::MCP] OAuth token verification failed: #{e.message}")
          failure(:invalid_token)
        end

        def metadata(resource_name: nil)
          supported = @scopes_supported || scopes

          {
            resource: resource,
            authorization_servers: authorization_servers,
            scopes_supported: supported.empty? ? nil : supported,
            bearer_methods_supported: [ "header" ],
            resource_name: resource_name
          }.compact
        end

        # Value of the WWW-Authenticate header for a 401 or 403 response.
        def challenge(realm:, error: nil)
          params = { realm: realm, resource_metadata: metadata_url }
          params[:error] = error.to_s if error
          params[:scope] = scopes.join(" ") unless scopes.empty?

          "Bearer " + params.map { |key, value| %(#{key}="#{value}") }.join(", ")
        end

        # Served by RackApp under the MCP endpoint itself, so it works wherever
        # the server is mounted.
        def metadata_url
          "#{resource.chomp('/')}#{METADATA_PATH}"
        end

        def resource
          OAuth.resolve(@resource).to_s
        end

        def authorization_servers
          Array(OAuth.resolve(@authorization_servers)).map(&:to_s)
        end

        private

        def build_verifier(jwks_uri, algorithms, introspection, verify_token)
          given = { jwks_uri: jwks_uri, introspection: introspection, verify_token: verify_token }.compact
          unless given.size == 1
            raise ArgumentError, "authenticate :oauth requires exactly one of jwks_uri:, introspection: or verify_token:"
          end

          if jwks_uri
            JWTVerifier.new(jwks_uri, algorithms: algorithms, leeway: LEEWAY)
          elsif introspection
            IntrospectionVerifier.new(**introspection.transform_keys(&:to_sym))
          else
            raise ArgumentError, "verify_token: must respond to #call" unless verify_token.respond_to?(:call)

            verify_token
          end
        end

        def verify(token, request)
          if @verifier.respond_to?(:arity) && @verifier.arity == 1
            @verifier.call(token)
          else
            @verifier.call(token, request)
          end
        end

        def valid?(access_token)
          claims = access_token.claims

          fresh?(claims) && trusted_issuer?(claims) && intended_audience?(access_token)
        end

        def fresh?(claims)
          now = Time.now.to_i
          return false if claims.key?("exp") && !(claims["exp"].is_a?(Numeric) && now < claims["exp"] + LEEWAY)
          return false if claims.key?("nbf") && !(claims["nbf"].is_a?(Numeric) && now >= claims["nbf"] - LEEWAY)

          true
        end

        # JWTs must carry `iss`; introspection responses and custom verifiers may omit it.
        def trusted_issuer?(claims)
          return true unless claims.key?("iss")

          authorization_servers.map { |server| normalize(server) }.include?(normalize(claims["iss"]))
        end

        # RFC 8707: the token must have been issued for this server. Tokens
        # meant for another resource are rejected, never passed through.
        def intended_audience?(access_token)
          expected = Array(OAuth.resolve(@audience) || resource).map { |value| normalize(value) }

          access_token.audience.any? { |value| expected.include?(normalize(value)) }
        end

        def normalize(uri)
          uri.to_s.chomp("/")
        end

        def validate_resource!(resource)
          uri = URI.parse(resource.to_s)
          return if uri.is_a?(URI::HTTP) && uri.host && uri.fragment.nil?

          raise ArgumentError, "resource: must be the absolute http(s) URL of the MCP endpoint, without a fragment"
        rescue URI::InvalidURIError
          raise ArgumentError, "resource: #{resource.inspect} is not a valid URL"
        end

        def failure(error)
          Authenticator::Result.new(false, nil, error, nil)
        end
      end
    end
  end
end
