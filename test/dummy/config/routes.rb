Rails.application.routes.draw do
  mount OmniAgent::Engine => "/omni_agent"
  mcp_servers
end
