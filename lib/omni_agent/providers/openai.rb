# lib/omni_agent/providers/openai.rb
require "json"

module OmniAgent
  module Providers
    class OpenAI < Base
      begin
        require "openai"
      rescue LoadError
        raise OmniAgent::MissingDependencyError,
              "The 'openai' gem is required to use the OpenAI provider. " \
              "Please add `gem 'openai'` to your Gemfile."
      end

      def chat(messages:, tools: [], **options)
        validate_messages!(messages, allowed_roles: %i[system user assistant tool])
        openai_tools = tools.map { |tool| format_tool(tool) }

        payload = {
          model: model,
          messages: messages
        }
        payload[:tools] = openai_tools if openai_tools.any?
        payload.merge!(options) if options.any?

        response = client.chat.completions.create(**payload)

        parse_response(response)
      rescue => e
        raise OmniAgent::Error, "Error during OpenAI chat: #{e.message}"
      end

      protected

      def client
        @client ||= ::OpenAI::Client.new(api_key: @api_key)
      end

      def default_api_key
        ENV.fetch("OPENAI_ACCESS_TOKEN", nil)
      end

      def default_model
        "gpt-4o-mini"
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
        provider_raw_response = raw_response.respond_to?(:to_h) ? raw_response.to_h : raw_response
        choices = raw_response.respond_to?(:choices) ? raw_response.choices : provider_raw_response["choices"]
        first_choice = choices&.first || {}

        message = first_choice.respond_to?(:message) ? first_choice.message : (first_choice["message"] || {})
        content = message.respond_to?(:content) ? message.content : message["content"]

        raw_tool_calls = message.respond_to?(:tool_calls) ? message.tool_calls : message["tool_calls"]
        raw_tool_calls ||= []

        tool_calls = raw_tool_calls.map do |tc|
          fn = tc.respond_to?(:function) ? tc.function : tc["function"]
          {
            id: tc.respond_to?(:id) ? tc.id : tc["id"],
            name: fn.respond_to?(:name) ? fn.name : fn["name"],
            arguments: JSON.parse((fn.respond_to?(:arguments) ? fn.arguments : fn["arguments"]) || "{}")
          }
        end

        OmniAgent::Providers::Response.new(
          content: content,
          raw_response: provider_raw_response,
          tool_calls: tool_calls
        )
      end
    end
  end
end
