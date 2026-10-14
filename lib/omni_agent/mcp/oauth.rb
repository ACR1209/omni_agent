module OmniAgent
  module MCP
    # Resource server side of the MCP authorization spec (OAuth 2.1). Access
    # tokens are issued by an external authorization server and validated here;
    # see ResourceServer.
    module OAuth
      # The authorization server could not be reached or answered with something
      # unusable. The request is rejected as unauthenticated.
      class VerificationError < OmniAgent::MCPError; end

      # Settings accept a value or a callable, so they can be read from ENV or
      # credentials on every request.
      def self.resolve(value)
        value.respond_to?(:call) ? value.call : value
      end
    end
  end
end
