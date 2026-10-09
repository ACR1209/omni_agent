require "json"

module OmniAgent
  module MCP
    # Streamable HTTP transport, stateless: every POST carries one JSON-RPC
    # message and gets a plain JSON response. No SSE stream, no sessions.
    class RackApp
      JSON_HEADERS = { "content-type" => "application/json" }.freeze
      PARSE_FAILED = Object.new.freeze

      # Accepts the server class or its name. Passing a String defers the
      # constant lookup to request time, which keeps routes reload-safe.
      def initialize(server)
        @server = server
      end

      def call(env)
        server_class = MCP.resolve_server_class(@server)
        request = Request.new(env)

        return forbidden unless origin_allowed?(request, server_class)

        auth = Authenticator.new(server_class).authenticate(request)
        return unauthorized(server_class) unless auth.authenticated?

        return method_not_allowed unless request.post?

        if request.protocol_version && !SUPPORTED_PROTOCOL_VERSIONS.include?(request.protocol_version)
          return http_error(400, "Unsupported MCP-Protocol-Version: #{request.protocol_version}")
        end

        body = read_body(request)
        return http_error(413, "Request body too large") if body.nil?

        message = parse_json(body)
        return json_response(400, parse_error_response) if message.equal?(PARSE_FAILED)

        server = server_class.new(principal: auth.principal, request: request, transport: :http)
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

      def method_not_allowed
        [ 405, JSON_HEADERS.merge("allow" => "POST"), [ JSON.generate({ error: "Method not allowed" }) ] ]
      end

      def unauthorized(server_class)
        headers = JSON_HEADERS.merge("www-authenticate" => %(Bearer realm="#{server_class.server_name}"))
        [ 401, headers, [ JSON.generate({ error: "Unauthorized" }) ] ]
      end
    end
  end
end
