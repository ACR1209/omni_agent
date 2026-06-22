
module OmniAgent
  module Providers
    def self.registry
      {
        openai: OmniAgent::Providers::OpenAI,
        mock: OmniAgent::Providers::Mock,
        mock_judge: OmniAgent::Providers::MockJudge
      }
    end
  end
end
