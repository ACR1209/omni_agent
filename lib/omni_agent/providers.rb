
module OmniAgent
  module Providers
    def self.registry
      {
        openai: OmniAgent::Providers::OpenAI,
        ollama: OmniAgent::Providers::Ollama,
        mock: OmniAgent::Providers::Mock,
        mock_judge: OmniAgent::Providers::MockJudge
      }
    end
  end
end
