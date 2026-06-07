class ResearchAgent < OmniAgent::Agent
  provider :openai, model: "gpt-4o-mini"
end