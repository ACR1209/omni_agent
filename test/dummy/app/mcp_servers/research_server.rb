class ResearchServer < OmniAgent::MCP::Server
  server_version "1.0.0"
  instructions "Weather lookups and ticket management for the dummy app."

  tools ResearchAgent::Tools::GetWeather
  tools_from TaskAgent
  expose_agent AliasAgent, as: "ask_alias_agent", description: "Ask the alias agent a question.", forward: [ :current_user ]

  authenticate :bearer, tokens: -> { ENV.fetch("RESEARCH_MCP_TOKENS", "").split(",") }

  context { |principal, _request| { current_user: principal } }
end
