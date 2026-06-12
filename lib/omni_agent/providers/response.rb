module OmniAgent
  module Providers
    class Response
      attr_reader :content, :tool_calls, :raw_response, :raw_request, :generated_messages

      def initialize(content:, tool_calls: [], raw_response: nil, raw_request: nil, generated_messages: [])
        @content = content
        @tool_calls = tool_calls || []
        @raw_response = raw_response
        @raw_request = raw_request
        @generated_messages = generated_messages || []
      end

      def tool_calls?
        @tool_calls.any?
      end

      def answer
        @content
      end

      def with_generated_messages(messages)
        @generated_messages = Array(messages)
        self
      end
    end
  end
end
