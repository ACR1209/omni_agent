require "uri"

module OmniAgent
  module MCP
    module OAuth
      # Asks the authorization server whether a token is active (RFC 7662).
      # Works with opaque tokens. Returns the introspection response, or nil
      # when the token is not active.
      class IntrospectionVerifier
        def initialize(url:, client_id: nil, client_secret: nil)
          raise ArgumentError, "introspection: requires url:" if url.nil?

          @url = url
          @client_id = client_id
          @client_secret = client_secret
        end

        def call(token, _request = nil)
          response = HTTPClient.post_form_json(
            OAuth.resolve(@url),
            { "token" => token, "token_type_hint" => "access_token" },
            basic_auth: credentials
          )
          response.is_a?(Hash) && response["active"] == true ? response : nil
        end

        def inspect
          "#<#{self.class.name} url=#{@url.inspect}>"
        end

        private

        # client_secret_basic: RFC 6749 section 2.3.1 form-encodes both values.
        def credentials
          client_id = OAuth.resolve(@client_id)
          return if client_id.nil?

          [ client_id, OAuth.resolve(@client_secret) ].map { |value| URI.encode_www_form_component(value.to_s) }
        end
      end
    end
  end
end
