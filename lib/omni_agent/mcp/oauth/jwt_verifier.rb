module OmniAgent
  module MCP
    module OAuth
      # Verifies JWT access tokens (RFC 9068) with the authorization server's
      # JSON Web Key Set. Returns the payload, or nil when the token is invalid.
      # Issuer, audience and scopes are checked afterwards by ResourceServer.
      class JWTVerifier
        # Asymmetric algorithms only: a JWKS publishes public keys.
        DEFAULT_ALGORITHMS = %w[RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 ES512].freeze
        CACHE_TTL = 300
        # A token signed with an unknown `kid` refetches the key set (key
        # rotation), but at most this often, so forged tokens cannot make every
        # request call the authorization server.
        MIN_REFRESH_INTERVAL = 30

        def self.require_jwt!
          require "jwt"
        rescue LoadError
          raise OmniAgent::MissingDependencyError,
                "The 'jwt' gem is required for `authenticate :oauth, jwks_uri: ...`. " \
                "Please add `gem 'jwt'` to your Gemfile."
        end

        def initialize(jwks_uri, algorithms: DEFAULT_ALGORITHMS, leeway: 0)
          self.class.require_jwt!

          @jwks_uri = jwks_uri
          @algorithms = Array(algorithms).map(&:to_s)
          @leeway = leeway
          @mutex = Mutex.new
          @jwks = nil
          @fetched_at = nil
        end

        def call(token, _request = nil)
          payload, _header = ::JWT.decode(
            token, nil, true,
            algorithms: @algorithms,
            jwks: method(:jwks),
            required_claims: %w[exp iss],
            leeway: @leeway
          )
          payload
        rescue ::JWT::DecodeError
          nil
        end

        private

        # Key loader for JWT.decode. Called with `kid_not_found: true` when the
        # token's `kid` is not in the cached set.
        def jwks(options = {})
          @mutex.synchronize do
            fetch_jwks if refresh?(options)
            @jwks
          end
        end

        def refresh?(options)
          return true if @jwks.nil?

          age = monotonic_now - @fetched_at
          age > CACHE_TTL || (options[:kid_not_found] && age > MIN_REFRESH_INTERVAL)
        end

        def fetch_jwks
          @jwks = HTTPClient.get_json(OAuth.resolve(@jwks_uri))
          @fetched_at = monotonic_now
        rescue VerificationError => e
          raise if @jwks.nil?

          # Keep serving the cached keys while the authorization server is down.
          MCP.logger&.warn("[OmniAgent::MCP] Could not refresh JWKS, using cached keys: #{e.message}")
          @fetched_at = monotonic_now
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
