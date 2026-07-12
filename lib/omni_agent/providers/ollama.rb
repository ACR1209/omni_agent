# lib/omni_agent/providers/ollama.rb
module OmniAgent
  module Providers
    class Ollama < OpenAI
      protected

      def provider_label
        "Ollama"
      end

      def client
        @client ||= ::OpenAI::Client.new(api_key: @api_key, base_url: base_url)
      end

      def default_api_key
        ENV.fetch("OLLAMA_API_KEY", "ollama")
      end

      def default_model
        ENV.fetch("OLLAMA_MODEL", "llama3.1")
      end

      private

      def base_url
        "#{ENV.fetch('OLLAMA_HOST', 'http://localhost:11434')}/v1"
      end
    end
  end
end
