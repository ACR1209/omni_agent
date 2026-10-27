# EmbedJob (has_embedding later:) needs ActiveJob. Loading its railtie here,
# during Bundler.require, also works in apps that don't require it themselves.
require "active_job/railtie"

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
