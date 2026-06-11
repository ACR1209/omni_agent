module OmniAgent
  module Providers
    class Response
      attr_reader :content, :tool_calls, :raw_response, :raw_request

      def initialize(content:, tool_calls: [], raw_response: nil, raw_request: nil)
        @content = content
        @tool_calls = tool_calls || []
        @raw_response = raw_response
        @raw_request = raw_request
      end

      def tool_calls?
        @tool_calls.any?
      end

      def answer
        @content
      end
    end
  end
end
