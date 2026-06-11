# lib/omni_agents/providers/base.rb
module OmniAgent
  module Providers
    class Base
      attr_reader :model

      def initialize(api_key: nil, model: nil)
        @api_key = api_key || default_api_key
        @model = model || default_model
      end

      def chat(messages:, tools: [], **_options)
        raise NotImplementedError, "Providers must implement #chat"
      end

      def validate_messages!(messages, allowed_roles:)
        unless messages.is_a?(Array)
          raise OmniAgent::Error, "messages must be an array"
        end

        normalized_roles = Array(allowed_roles).map(&:to_s)

        messages.each_with_index do |message, index|
          unless message.is_a?(Hash)
            raise OmniAgent::Error, "message at index #{index} must be a hash"
          end

          role = message[:role] || message["role"]
          if role.nil?
            raise OmniAgent::Error, "message at index #{index} is missing role"
          end

          role_name = role.to_s
          unless normalized_roles.include?(role_name)
            raise OmniAgent::Error, "invalid message role '#{role_name}' at index #{index}"
          end

          validate_message_payload!(message, index, role_name)
        end
      end

      protected

      def default_api_key
        raise NotImplementedError, "Providers must define a default API key lookup"
      end

      def default_model
        raise NotImplementedError, "Providers must define a default model"
      end

      def validate_message_payload!(message, index, role_name)
        has_content = message.key?(:content) || message.key?("content")
        content_value = message[:content] || message["content"]

        case role_name
        when "assistant"
          has_tool_calls = message.key?(:tool_calls) || message.key?("tool_calls")
          return if has_content || has_tool_calls

          raise OmniAgent::Error, "assistant message at index #{index} must include content or tool_calls"
        when "tool"
          tool_call_id = message[:tool_call_id] || message["tool_call_id"]
          tool_name = message[:name] || message["name"]
          unless tool_call_id && tool_name && has_content
            raise OmniAgent::Error, "tool message at index #{index} must include tool_call_id, name, and content"
          end
        else
          unless has_content
            raise OmniAgent::Error, "#{role_name} message at index #{index} must include content"
          end
        end

        if has_content && content_value.nil?
          raise OmniAgent::Error, "message content at index #{index} cannot be nil"
        end
      end
    end
  end
end
