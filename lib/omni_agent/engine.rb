module OmniAgent
  class Engine < ::Rails::Engine
    isolate_namespace OmniAgent

    initializer "omni_agent.mcp_routing" do
      ActionDispatch::Routing::Mapper.include(OmniAgent::MCP::Routing)
    end

    initializer "omni_agent.embeddable" do
      ActiveSupport.on_load(:active_record) { extend OmniAgent::Embeddable }
    end
  end
end
