
module OmniAgent
  module Providers
    def self.registry
      {
        openai: OmniAgent::Providers::OpenAI,
        mock: OmniAgent::Providers::Mock
      }
    end
  end
end
