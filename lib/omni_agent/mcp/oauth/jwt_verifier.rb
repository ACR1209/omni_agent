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
        # request call the authorization server. Also the wait after a failed fetch.
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
          # Held only while fetching, so at most one fetch runs at a time.
          # Reading the cached keys never takes it.
          @fetch_mutex = Mutex.new
          @jwks = nil
          @fetched_at = nil
          @failed_at = nil
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
          if @jwks.nil?
            load_initial_jwks
          elsif refresh_due?(options) && @fetch_mutex.try_lock
            # Only the thread that got the lock refreshes; the others keep
            # using the cached keys instead of waiting for it.
            begin
              fetch_jwks
            ensure
              @fetch_mutex.unlock
            end
          end

          @jwks
        end

        # With no keys yet, concurrent requests wait for one shared fetch rather
        # than each fetching in turn. After a failure they fail fast until
        # MIN_REFRESH_INTERVAL has passed, so a down authorization server does
        # not tie up every app thread on timeouts.
        def load_initial_jwks
          raise_unavailable if backing_off?

          @fetch_mutex.synchronize do
            next if @jwks
            raise_unavailable if backing_off?

            fetch_jwks
          end

          raise_unavailable if @jwks.nil?
        end

        def refresh_due?(options)
          return false if backing_off?

          age = monotonic_now - @fetched_at
          age > CACHE_TTL || (options[:kid_not_found] && age > MIN_REFRESH_INTERVAL)
        end

        def fetch_jwks
          keys = HTTPClient.get_json(OAuth.resolve(@jwks_uri))
          # @fetched_at first: readers that see @jwks expect it to be set.
          @fetched_at = monotonic_now
          @jwks = keys
          @failed_at = nil
        rescue VerificationError => e
          @failed_at = monotonic_now
          fallback = @jwks ? "using cached keys" : "retrying in #{MIN_REFRESH_INTERVAL}s"
          MCP.logger&.warn("[OmniAgent::MCP] Could not fetch JWKS, #{fallback}: #{e.message}")
        end

        def backing_off?
          failed_at = @failed_at
          !failed_at.nil? && monotonic_now - failed_at < MIN_REFRESH_INTERVAL
        end

        def raise_unavailable
          raise VerificationError, "JWKS from #{OAuth.resolve(@jwks_uri)} is unavailable"
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
