# lib/omni_agents/providers/openai.rb
module OmniAgents
  module Providers
    class OpenAI < Base
      begin
        require 'openai'
      rescue LoadError
        raise OmniAgents::MissingDependencyError, 
              "The 'ruby-openai' gem is required to use the OpenAI provider. " \
              "Please add `gem 'ruby-openai'` to your Gemfile."
      end
        
      def chat(messages:, tools: [])
        # TODO: Add tool handling once we have a standardized way to define tools and their JSON schema        
        payload = {
          model: model,
          messages: messages
        }

        response = client.chat(parameters: payload)

        parse_response(response)
      end

      protected

      def client
        @client ||= ::OpenAI::Client.new(access_token: @api_key)
      end

      def default_api_key
        ENV.fetch('OPENAI_ACCESS_TOKEN', nil)
      end

      def default_model
        "gpt-4o"
      end

      private

      def parse_response(raw_response)
        message = raw_response.dig("choices", 0, "message") || {}
        
        content = message["content"]

        OmniAgents::Providers::Response.new(
          content: content,
          raw_response: raw_response
        )
      end
    end
  end
end