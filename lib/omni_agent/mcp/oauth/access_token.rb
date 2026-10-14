module OmniAgent
  module MCP
    module OAuth
      # A validated access token and its claims (JWT payload or introspection
      # response). It is the principal unless `authenticate :oauth` has a block.
      class AccessToken
        attr_reader :token, :claims

        def initialize(token, claims)
          @token = token
          @claims = claims.transform_keys(&:to_s).freeze
        end

        def [](key)
          claims[key.to_s]
        end

        def subject
          claims["sub"]
        end

        def issuer
          claims["iss"]
        end

        def client_id
          claims["client_id"] || claims["azp"]
        end

        def audience
          Array(claims["aud"]).map(&:to_s)
        end

        # RFC 9068 / RFC 7662 use a space-separated "scope"; some providers
        # (Okta, Entra ID) use "scp", as a string or an array.
        def scopes
          raw = claims.key?("scope") ? claims["scope"] : claims["scp"]
          raw.is_a?(Array) ? raw.map(&:to_s) : raw.to_s.split
        end

        def scope?(*names)
          (names.flatten.map(&:to_s) - scopes).empty?
        end

        def expires_at
          Time.at(claims["exp"]) if claims["exp"].is_a?(Numeric)
        end

        def to_s
          subject.to_s
        end

        # Never print the raw token.
        def inspect
          "#<#{self.class.name} sub=#{subject.inspect} client_id=#{client_id.inspect} scopes=#{scopes.inspect}>"
        end
      end
    end
  end
end
