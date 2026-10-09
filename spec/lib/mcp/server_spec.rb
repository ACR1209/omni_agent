require_relative "mcp_spec_helper"

RSpec.describe OmniAgent::MCP::Server do
  def build_server(name = "SpecServer", &block)
    klass = Class.new(described_class)
    stub_const(name, klass)
    klass.class_eval(&block) if block
    klass
  end

  describe "metadata" do
    it "defaults server_name to the underscored class name without _server" do
      expect(build_server("SupportServer").server_name).to eq("support")
    end

    it "keeps namespaced names readable" do
      expect(build_server("Internal::BillingServer").server_name).to eq("billing")
    end

    it "defaults server_version to 0.1.0" do
      expect(build_server.server_version).to eq("0.1.0")
    end

    it "stores explicit name, version and instructions" do
      server = build_server do
        server_name "custom"
        server_version "2.0.0"
        instructions "Use carefully."
      end

      expect([ server.server_name, server.server_version, server.instructions ]).to eq([ "custom", "2.0.0", "Use carefully." ])
    end
  end

  describe ".tool_registry" do
    it "registers tools by demodulized class name in declaration order" do
      server = build_server { tools MCPSpecTools::Echo, MCPSpecTools::Boom }

      expect(server.tool_registry).to eq("Echo" => MCPSpecTools::Echo, "Boom" => MCPSpecTools::Boom)
    end

    it "supports name overrides" do
      server = build_server { tool MCPSpecTools::Echo, as: "say_back" }

      expect(server.tool_registry.keys).to eq([ "say_back" ])
    end

    it "resolves tools given as strings lazily" do
      server = build_server { tools "MCPSpecTools::Echo" }

      expect(server.tool_registry).to eq("Echo" => MCPSpecTools::Echo)
    end

    it "raises on duplicate names" do
      server = build_server do
        tool MCPSpecTools::Echo
        tool MCPSpecTools::Boom, as: "Echo"
      end

      expect { server.tool_registry }.to raise_error(OmniAgent::MCPError, /Duplicate MCP tool name "Echo"/)
    end

    it "raises on invalid names" do
      server = build_server { tool MCPSpecTools::Echo, as: "has spaces" }

      expect { server.tool_registry }.to raise_error(OmniAgent::MCPError, /Invalid MCP tool name/)
    end

    it "raises when given something that is not a tool" do
      server = build_server { tool String, as: "string" }

      expect { server.tool_registry }.to raise_error(OmniAgent::MCPError, /not an OmniAgent::Tool subclass/)
    end

    it "pulls every tool from an agent with tools_from" do
      agent = Class.new(OmniAgent::Agent)
      stub_const("SpecToolsAgent", agent)
      stub_const("SpecToolsAgent::Tools", Module.new)
      stub_const("SpecToolsAgent::Tools::Echo", Class.new(MCPSpecTools::Echo))

      server = build_server { tools_from SpecToolsAgent }

      expect(server.tool_registry).to eq("Echo" => SpecToolsAgent::Tools::Echo)
    end

    it "exposes an agent as a tool" do
      agent = Class.new(OmniAgent::Agent)
      stub_const("SpecExposedAgent", agent)

      server = build_server { expose_agent SpecExposedAgent, as: :research, description: "Ask research" }
      tool_class = server.tool_registry.fetch("research")

      expect(tool_class.description).to eq("Ask research")
      expect(tool_class.json_schema[:required]).to eq([ "input" ])
    end

    it "rejects expose_agent with a non-agent" do
      expect { build_server { expose_agent String, as: :nope } }.to raise_error(ArgumentError, /OmniAgent::Agent subclass/)
    end
  end

  describe "Tools namespace" do
    def stub_namespace_tool(server_name, tool_name, parent = MCPSpecTools::Echo)
      stub_const("#{server_name}::Tools", Module.new) unless Object.const_get(server_name).const_defined?(:Tools, false)
      stub_const("#{server_name}::Tools::#{tool_name}", Class.new(parent))
    end

    it "auto-registers tools under <Server>::Tools, sorted by name" do
      build_server("NamespacedServer")
      stub_namespace_tool("NamespacedServer", "Zeta")
      stub_namespace_tool("NamespacedServer", "Alpha")
      stub_const("NamespacedServer::Tools::HELPER", 1)

      expect(NamespacedServer.tool_registry).to eq(
        "Alpha" => NamespacedServer::Tools::Alpha,
        "Zeta" => NamespacedServer::Tools::Zeta
      )
    end

    it "lists namespace tools before declared tools" do
      build_server("MixedServer") { tool MCPSpecTools::Boom, as: "boom" }
      stub_namespace_tool("MixedServer", "Local")

      expect(MixedServer.tool_registry.keys).to eq(%w[Local boom])
    end

    it "raises when a declared tool collides with a namespace tool" do
      build_server("CollidingServer") { tool MCPSpecTools::Boom, as: "Local" }
      stub_namespace_tool("CollidingServer", "Local")

      expect { CollidingServer.tool_registry }.to raise_error(OmniAgent::MCPError, /Duplicate MCP tool name "Local"/)
    end

    it "includes a parent server's namespace tools once, plus the child's own" do
      build_server("ParentNsServer")
      stub_namespace_tool("ParentNsServer", "Shared")
      stub_const("ChildNsServer", Class.new(ParentNsServer))

      expect(ChildNsServer.tool_registry.keys).to eq(%w[Shared])

      stub_namespace_tool("ChildNsServer", "Own")

      expect(ChildNsServer.tool_registry.keys).to eq(%w[Shared Own])
    end

    it "returns no namespace tools when the server has no Tools namespace" do
      expect(build_server("PlainServer").namespace_tool_classes).to eq([])
    end
  end

  describe "inheritance" do
    it "inherits settings and tools from a parent server" do
      parent = build_server("ApplicationSpecServer") do
        authenticate :none
        tools MCPSpecTools::Echo
        allowed_origins "https://a.example"
      end
      child = Class.new(parent)
      stub_const("ChildSpecServer", child)
      child.tools MCPSpecTools::Boom
      child.allowed_origins "https://b.example"

      expect(child.configured_authentication).to eq(strategy: :none)
      expect(child.tool_registry.keys).to eq(%w[Echo Boom])
      expect(child.configured_allowed_origins).to eq(%w[https://a.example https://b.example])
      expect(child.server_name).to eq("child_spec")
      expect(parent.tool_registry.keys).to eq(%w[Echo])
    end
  end

  describe "#visible_tools" do
    it "applies authorize_tool per principal" do
      server = build_server do
        tools MCPSpecTools::Echo, MCPSpecTools::Admin
        authorize_tool { |tool_class, principal| principal == :admin || !tool_class.tags.include?(:admin) }
      end

      expect(server.new(principal: :guest).visible_tools.keys).to eq(%w[Echo])
      expect(server.new(principal: :admin).visible_tools.keys).to eq(%w[Echo Admin])
      expect(server.new(principal: :guest).find_tool("Admin")).to be_nil
    end

    it "passes the registered name to authorize_tool" do
      server = build_server do
        tool MCPSpecTools::Echo, as: "allowed"
        tool MCPSpecTools::Boom, as: "blocked"
        authorize_tool { |_tool_class, _principal, name| name == "allowed" }
      end

      expect(server.new.visible_tools.keys).to eq(%w[allowed])
    end
  end

  describe "#tool_context" do
    it "includes principal and request" do
      context = build_server.new(principal: :ci, request: :req).tool_context

      expect(context).to eq(mcp_principal: :ci, mcp_request: :req)
    end

    it "merges the context block result" do
      server = build_server { context { |principal, _request| { current_user: "user:#{principal}" } } }

      expect(server.new(principal: 7).tool_context).to include(current_user: "user:7", mcp_principal: 7)
    end
  end

  describe "DSL validation" do
    it "requires tokens for bearer auth" do
      expect { build_server { authenticate :bearer } }.to raise_error(ArgumentError, /tokens:/)
    end

    it "rejects unknown strategies" do
      expect { build_server { authenticate :basic } }.to raise_error(ArgumentError)
    end
  end
end
