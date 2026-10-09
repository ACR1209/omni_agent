module OmniAgent
  module MCP
    class Handler
      class ProtocolError < StandardError
        attr_reader :code

        def initialize(code, message)
          super(message)
          @code = code
        end
      end

      def initialize(server)
        @server = server
      end

      # Takes a parsed JSON-RPC message and returns the response Hash, or nil
      # when no response is due (notifications and client responses).
      def call(message)
        unless message.is_a?(Hash)
          reason = message.is_a?(Array) ? "Batch requests are not supported" : "Invalid Request"
          return error_response(nil, INVALID_REQUEST, reason)
        end

        message = message.transform_keys(&:to_s)
        return nil if client_response?(message)

        id = message["id"]
        notification = !message.key?("id")

        unless message["jsonrpc"] == JSONRPC_VERSION && message["method"].is_a?(String)
          return notification ? nil : error_response(id, INVALID_REQUEST, "Invalid Request")
        end

        return nil if notification

        result = dispatch(message["method"], message["params"])
        success_response(id, result)
      rescue ProtocolError => e
        error_response(id, e.code, e.message)
      rescue StandardError => e
        log_error("MCP internal error", e)
        error_response(id, INTERNAL_ERROR, "Internal error")
      end

      private

      attr_reader :server

      def dispatch(method, params)
        params = normalize_params(params)

        case method
        when "initialize" then initialize_result(params)
        when "ping" then {}
        when "tools/list" then tools_list_result
        when "tools/call" then tools_call_result(params)
        else
          raise ProtocolError.new(METHOD_NOT_FOUND, "Method not found: #{method}")
        end
      end

      def normalize_params(params)
        return {} if params.nil?
        raise ProtocolError.new(INVALID_PARAMS, "params must be an object") unless params.is_a?(Hash)

        params.transform_keys(&:to_s)
      end

      def initialize_result(params)
        requested = params["protocolVersion"]
        protocol_version = SUPPORTED_PROTOCOL_VERSIONS.include?(requested) ? requested : LATEST_PROTOCOL_VERSION
        server_class = server.class

        result = {
          protocolVersion: protocol_version,
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name: server_class.server_name, version: server_class.server_version }
        }
        result[:instructions] = server_class.instructions if server_class.instructions
        result
      end

      def tools_list_result
        tools = server.visible_tools.map { |name, tool_class| ToolAdapter.definition(name, tool_class) }
        { tools: tools }
      end

      def tools_call_result(params)
        name = params["name"]
        raise ProtocolError.new(INVALID_PARAMS, "Missing tool name") unless name.is_a?(String)

        tool_class = server.find_tool(name)
        raise ProtocolError.new(INVALID_PARAMS, "Unknown tool: #{name}") unless tool_class

        arguments = params["arguments"] || {}
        raise ProtocolError.new(INVALID_PARAMS, "arguments must be an object") unless arguments.is_a?(Hash)

        execute_tool(name, tool_class, arguments)
      end

      def execute_tool(name, tool_class, arguments)
        tool = tool_class.new
        tool.context = server.tool_context
        ToolAdapter.result(tool.invoke(arguments))
      rescue StandardError => e
        log_error("MCP tool #{name} failed", e)
        ToolAdapter.error_result("Error executing tool: #{e.message}")
      end

      def client_response?(message)
        !message.key?("method") && (message.key?("result") || message.key?("error"))
      end

      def success_response(id, result)
        { jsonrpc: JSONRPC_VERSION, id: id, result: result }
      end

      def error_response(id, code, message)
        { jsonrpc: JSONRPC_VERSION, id: id, error: { code: code, message: message } }
      end

      def log_error(prefix, error)
        MCP.logger&.error("[OmniAgent::MCP] #{prefix}: #{error.class}: #{error.message}")
      end
    end
  end
end
