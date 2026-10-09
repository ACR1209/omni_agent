require "rack"

module OmniAgent
  module MCP
    class Request < Rack::Request
      def bearer_token
        header = get_header("HTTP_AUTHORIZATION").to_s
        match = header.match(/\ABearer\s+(.+)\z/i)
        return if match.nil?

        token = match[1].strip
        token.empty? ? nil : token
      end

      def protocol_version
        get_header("HTTP_MCP_PROTOCOL_VERSION")
      end

      def origin
        get_header("HTTP_ORIGIN")
      end
    end
  end
end
