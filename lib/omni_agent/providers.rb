
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

    def self.fetch(name)
      registry.fetch(name.to_sym) do
        raise OmniAgent::UnknownProviderError,
              "Unknown provider #{name.inspect}. Known providers: #{registry.keys.join(', ')}"
      end
    end
  end
end
