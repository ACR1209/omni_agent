
module OmniAgent
  module Providers
    def self.registry
      {
        openai: OmniAgent::Providers::OpenAI 
      }
    end
  end
end