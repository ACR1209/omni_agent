class TaskAgent < OmniAgent::Agent
  provider :openai, model: "gpt-4o-mini"
end
