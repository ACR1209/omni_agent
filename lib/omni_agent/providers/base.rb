# lib/omni_agents/providers/base.rb
module OmniAgent
  module Providers
    class Base
      attr_reader :model

      def initialize(api_key: nil, model: nil)
        @api_key = api_key || default_api_key
        @model = model || default_model
      end

      def chat(messages:, tools: [])
        raise NotImplementedError, "Providers must implement #chat"
      end

      protected

      def default_api_key
        raise NotImplementedError, "Providers must define a default API key lookup"
      end

      def default_model
        raise NotImplementedError, "Providers must define a default model"
      end
    end
  end
end