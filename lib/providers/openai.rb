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
        openai_tools = tools.map { |tool| format_tool(tool) }

        payload = {
          model: model,
          messages: messages
        }
        payload[:tools] = openai_tools if openai_tools.any?

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

      def format_tool(tool_class)
        {
          type: "function",
          function: {
            name: tool_class.name.split("::").last,
            description: tool_class.description,
            parameters: tool_class.json_schema 
          }
        }
      end

      def parse_response(raw_response)
        message = raw_response.dig("choices", 0, "message") || {}
        
        content = message["content"]

        tool_calls = (message["tool_calls"] || []).map do |tc|
          {
            id: tc["id"],
            name: tc.dig("function", "name"),
            arguments: JSON.parse(tc.dig("function", "arguments") || "{}")
          }
        end

        OmniAgents::Providers::Response.new(
          content: content,
          raw_response: raw_response,
          tool_calls: tool_calls
        )
      end
    end
  end
end