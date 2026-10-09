module OmniAgent
  module MCP
    SUPPORTED_PROTOCOL_VERSIONS = [ "2025-11-25", "2025-06-18", "2025-03-26" ].freeze
    LATEST_PROTOCOL_VERSION = SUPPORTED_PROTOCOL_VERSIONS.first

    JSONRPC_VERSION = "2.0".freeze

    PARSE_ERROR = -32_700
    INVALID_REQUEST = -32_600
    METHOD_NOT_FOUND = -32_601
    INVALID_PARAMS = -32_602
    INTERNAL_ERROR = -32_603

    def self.logger
      return unless defined?(Rails) && Rails.respond_to?(:logger)

      Rails.logger
    end

    def self.resolve_server_class(server)
      return server if server.is_a?(Class)

      server_class = Object.const_get(server.to_s)
      unless server_class.is_a?(Class) && server_class < OmniAgent::MCP::Server
        raise OmniAgent::MCPError, "#{server} is not an OmniAgent::MCP::Server subclass"
      end

      server_class
    end
  end
end
