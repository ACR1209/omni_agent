module OmniAgent
  class Engine < ::Rails::Engine
    isolate_namespace OmniAgent

    initializer "omni_agent.mcp_routing" do
      ActionDispatch::Routing::Mapper.include(OmniAgent::MCP::Routing)
    end
  end
end
