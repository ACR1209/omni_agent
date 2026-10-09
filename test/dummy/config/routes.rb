Rails.application.routes.draw do
  mount OmniAgent::Engine => "/omni_agent"
  mount OmniAgent::MCP::RackApp.new("ResearchServer") => "/mcp/research"
end
