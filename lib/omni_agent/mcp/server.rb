require "active_support/core_ext/string/inflections"

module OmniAgent
  module MCP
    class Server
      TOOL_NAME_PATTERN = /\A[A-Za-z0-9_.-]{1,128}\z/

      class << self
        def server_name(value = nil)
          @server_name = value.to_s if value
          setting(:@server_name) || default_server_name
        end

        def server_version(value = nil)
          @server_version = value.to_s if value
          setting(:@server_version) || "0.1.0"
        end

        def instructions(text = nil)
          @instructions = text if text
          setting(:@instructions)
        end

        def tools(*tool_classes)
          tool_classes.flatten.each { |tool_class| tool(tool_class) }
        end

        def tool(tool_class, as: nil)
          add_tool_declaration(type: :tool, tool_class: tool_class, name: as&.to_s)
        end

        def tools_from(*agent_classes)
          agent_classes.flatten.each do |agent_class|
            add_tool_declaration(type: :agent_tools, agent_class: agent_class)
          end
        end

        def expose_agent(agent_class, as:, description: nil, run_alias: nil, forward: [])
          unless agent_class.is_a?(Class) && agent_class <= OmniAgent::Agent
            raise ArgumentError, "expose_agent requires an OmniAgent::Agent subclass"
          end

          tool_class = OmniAgent::Agent.build_delegated_tool_class(
            agent_class,
            description: description,
            run_alias: run_alias,
            forward: forward
          )

          add_tool_declaration(type: :tool, tool_class: tool_class, name: as.to_s)
        end

        def authenticate(strategy = nil, tokens: nil, &block)
          @authentication = if block
            { strategy: :custom, block: block }
          elsif strategy == :none
            { strategy: :none }
          elsif strategy == :bearer
            raise ArgumentError, "authenticate :bearer requires tokens:" if tokens.nil?

            { strategy: :bearer, tokens: tokens }
          else
            raise ArgumentError, "authenticate expects :bearer (with tokens:), :none, or a block"
          end
        end

        def authorize_tool(&block)
          raise ArgumentError, "authorize_tool requires a block" unless block

          @authorize_tool_block = block
        end

        def context(&block)
          raise ArgumentError, "context requires a block" unless block

          @context_block = block
        end

        def stdio_principal(&block)
          raise ArgumentError, "stdio_principal requires a block" unless block

          @stdio_principal_block = block
        end

        def allowed_origins(*origins)
          @allowed_origins = (@allowed_origins || []) + origins.flatten
        end

        def configured_tool_declarations; list_setting(:@tool_declarations); end
        def configured_authentication; setting(:@authentication); end
        def configured_authorize_tool_block; setting(:@authorize_tool_block); end
        def configured_context_block; setting(:@context_block); end
        def configured_stdio_principal_block; setting(:@stdio_principal_block); end
        def configured_allowed_origins; list_setting(:@allowed_origins); end

        # Ordered { "ToolName" => tool_class }. Resolved on every call so lazily
        # referenced tools (strings, tools_from) pick up code reloads.
        def tool_registry
          configured_tool_declarations.each_with_object({}) do |declaration, registry|
            resolve_declaration(declaration).each do |name, tool_class|
              register_tool(registry, name, tool_class)
            end
          end
        end

        def resolve_stdio_principal
          configured_stdio_principal_block&.call
        end

        private

        # Servers inherit settings from parent servers (e.g. an ApplicationMCPServer
        # that declares `authenticate` once). Scalars: nearest wins. Lists: concatenated.
        def server_ancestors
          ancestors.select { |klass| klass.is_a?(Class) && klass < OmniAgent::MCP::Server }
        end

        def setting(ivar)
          server_ancestors.each do |klass|
            value = klass.instance_variable_get(ivar)
            return value unless value.nil?
          end

          nil
        end

        def list_setting(ivar)
          server_ancestors.reverse.flat_map { |klass| klass.instance_variable_get(ivar) || [] }
        end

        def default_server_name
          return "omni_agent" if name.nil?

          base = name.demodulize.underscore
          base = base.delete_suffix("_server") unless base == "server"
          base
        end

        def add_tool_declaration(declaration)
          @tool_declarations = (@tool_declarations || []) + [ declaration ]
        end

        def resolve_declaration(declaration)
          case declaration[:type]
          when :tool
            tool_class = resolve_constant(declaration[:tool_class])
            [ [ declaration[:name] || default_tool_name(tool_class), tool_class ] ]
          when :agent_tools
            agent_class = resolve_constant(declaration[:agent_class])
            agent_class.tool_classes.map { |tool_class| [ default_tool_name(tool_class), tool_class ] }
          end
        end

        def resolve_constant(value)
          return value if value.is_a?(Class)

          Object.const_get(value.to_s)
        end

        def default_tool_name(tool_class)
          if tool_class.name.nil?
            raise OmniAgent::MCPError, "Anonymous tool classes need an explicit name: `tool klass, as: \"name\"`"
          end

          tool_class.name.demodulize
        end

        def register_tool(registry, name, tool_class)
          unless tool_class.is_a?(Class) && tool_class < OmniAgent::Tool
            raise OmniAgent::MCPError, "#{tool_class.inspect} is not an OmniAgent::Tool subclass"
          end

          unless name.match?(TOOL_NAME_PATTERN)
            raise OmniAgent::MCPError,
                  "Invalid MCP tool name #{name.inspect} in #{self.name}: use 1-128 characters from A-Z, a-z, 0-9, _, -, ."
          end

          if registry.key?(name)
            raise OmniAgent::MCPError,
                  "Duplicate MCP tool name #{name.inspect} in #{self.name}. Use `tool klass, as: \"other_name\"` to rename one."
          end

          registry[name] = tool_class
        end
      end

      attr_reader :principal, :request, :transport

      def initialize(principal: nil, request: nil, transport: :http)
        @principal = principal
        @request = request
        @transport = transport
      end

      def visible_tools
        authorizer = self.class.configured_authorize_tool_block
        registry = self.class.tool_registry
        return registry unless authorizer

        registry.select do |name, tool_class|
          instance_exec(tool_class, principal, name, &authorizer)
        end
      end

      def find_tool(name)
        visible_tools[name.to_s]
      end

      def tool_context
        base = { mcp_principal: principal, mcp_request: request }
        context_block = self.class.configured_context_block
        return base unless context_block

        extra = instance_exec(principal, request, &context_block)
        extra.is_a?(Hash) ? base.merge(extra) : base
      end
    end
  end
end
