Rails.application.routes.draw do
  mount OmniAgent::Engine => "/omni_agent"
end
