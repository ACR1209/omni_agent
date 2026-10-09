require "active_support/security_utils"

module OmniAgent
  module MCP
    class Authenticator
      Result = Struct.new(:authenticated, :principal) do
        def authenticated?
          authenticated == true
        end
      end

      ARRAY_TOKEN_PRINCIPAL = :bearer_token

      def initialize(server_class)
        @server_class = server_class
      end

      def authenticate(request)
        authentication = @server_class.configured_authentication

        if authentication.nil?
          raise OmniAgent::MCPError,
                "#{@server_class.name} does not declare authentication. " \
                "Add `authenticate :bearer, tokens: ...`, `authenticate { |request| ... }`, " \
                "or explicitly opt out with `authenticate :none`."
        end

        case authentication[:strategy]
        when :none
          success(nil)
        when :bearer
          authenticate_bearer(request, authentication[:tokens])
        when :custom
          principal = authentication[:block].call(request)
          principal ? success(principal) : failure
        end
      end

      private

      def authenticate_bearer(request, tokens)
        presented = request.bearer_token
        return failure if presented.nil?

        matched = false
        principal = nil

        # Compare against every configured token (no early exit) so response
        # timing does not reveal which token, or how many tokens, matched.
        token_candidates(tokens).each do |candidate_principal, token|
          next if token.nil? || token.to_s.empty?

          if ActiveSupport::SecurityUtils.secure_compare(token.to_s, presented) && !matched
            matched = true
            principal = candidate_principal
          end
        end

        matched ? success(principal) : failure
      end

      def token_candidates(tokens)
        tokens = tokens.call if tokens.respond_to?(:call)

        case tokens
        when Hash
          tokens.map { |principal, token| [ principal, token ] }
        else
          Array(tokens).map { |token| [ ARRAY_TOKEN_PRINCIPAL, token ] }
        end
      end

      def success(principal)
        Result.new(true, principal)
      end

      def failure
        Result.new(false, nil)
      end
    end
  end
end
