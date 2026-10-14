require "json"

module OmniAgent
  module MCP
    # Streamable HTTP transport, stateless: every POST carries one JSON-RPC
    # message and gets a plain JSON response. No SSE stream, no sessions.
    class RackApp
      JSON_HEADERS = { "content-type" => "application/json" }.freeze
      PARSE_FAILED = Object.new.freeze
      METADATA_CORS_HEADERS = {
        "access-control-allow-origin" => "*",
        "access-control-allow-methods" => "GET, OPTIONS",
        "access-control-allow-headers" => "mcp-protocol-version"
      }.freeze

      # Accepts the server class or its name. Passing a String defers the
      # constant lookup to request time, which keeps routes reload-safe.
      attr_reader :server

      def initialize(server)
        @server = server
      end

      def inspect
        "#<#{self.class.name} #{server}>"
      end

      def call(env)
        server_class = MCP.resolve_server_class(@server)
        request = Request.new(env)
        resource_server = server_class.configured_oauth_resource_server

        # Public, so clients can discover the authorization server before they have a token.
        if resource_server && request.path_info == OAuth::ResourceServer::METADATA_PATH
          return protected_resource_metadata(server_class, resource_server, request)
        end

        return forbidden unless origin_allowed?(request, server_class)

        auth = Authenticator.new(server_class).authenticate(request)
        return unauthorized(server_class, resource_server, auth) unless auth.authenticated?

        return method_not_allowed unless request.post?

        if request.protocol_version && !SUPPORTED_PROTOCOL_VERSIONS.include?(request.protocol_version)
          return http_error(400, "Unsupported MCP-Protocol-Version: #{request.protocol_version}")
        end

        body = read_body(request)
        return http_error(413, "Request body too large") if body.nil?

        message = parse_json(body)
        return json_response(400, parse_error_response) if message.equal?(PARSE_FAILED)

        server = server_class.new(principal: auth.principal, access_token: auth.access_token, request: request, transport: :http)
        response = Handler.new(server).call(message)
        return [ 202, {}, [] ] if response.nil?

        status = response[:error] && response[:id].nil? ? 400 : 200
        json_response(status, response)
      end

      private

      def origin_allowed?(request, server_class)
        origin = request.origin
        return true if origin.nil? || origin.empty?

        allowed = server_class.configured_allowed_origins + Array(OmniAgent.configuration.mcp_allowed_origins)
        allowed.any? do |pattern|
          pattern.is_a?(Regexp) ? pattern.match?(origin) : pattern.to_s == origin
        end
      end

      def read_body(request)
        max_bytes = OmniAgent.configuration.mcp_max_request_bytes
        return nil if request.content_length.to_i > max_bytes

        io = request.body
        return "" if io.nil?

        body = io.read(max_bytes + 1).to_s
        body.bytesize > max_bytes ? nil : body
      end

      def parse_json(body)
        JSON.parse(body)
      rescue JSON::ParserError
        PARSE_FAILED
      end

      def parse_error_response
        { jsonrpc: JSONRPC_VERSION, id: nil, error: { code: PARSE_ERROR, message: "Parse error" } }
      end

      def json_response(status, payload)
        [ status, JSON_HEADERS.dup, [ JSON.generate(payload) ] ]
      end

      def http_error(status, message)
        json_response(status, { error: message })
      end

      def forbidden
        http_error(403, "Origin not allowed")
      end

      def method_not_allowed(allow = "POST")
        [ 405, JSON_HEADERS.merge("allow" => allow), [ JSON.generate({ error: "Method not allowed" }) ] ]
      end

      def unauthorized(server_class, resource_server, auth)
        realm = server_class.server_name
        challenge = resource_server ? resource_server.challenge(realm: realm, error: auth.error) : %(Bearer realm="#{realm}")
        status, message = auth.error == :insufficient_scope ? [ 403, "Insufficient scope" ] : [ 401, "Unauthorized" ]

        [ status, JSON_HEADERS.merge("www-authenticate" => challenge), [ JSON.generate({ error: message }) ] ]
      end

      # RFC 9728 Protected Resource Metadata. Browser-based clients fetch it
      # cross-origin, and it holds nothing secret, so any origin may read it.
      def protected_resource_metadata(server_class, resource_server, request)
        return [ 204, METADATA_CORS_HEADERS.dup, [] ] if request.options?
        return method_not_allowed("GET") unless request.get? || request.head?

        metadata = resource_server.metadata(resource_name: server_class.server_name)
        [ 200, JSON_HEADERS.merge(METADATA_CORS_HEADERS), [ JSON.generate(metadata) ] ]
      end
    end
  end
end
