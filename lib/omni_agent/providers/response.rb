module OmniAgent
  module Providers
    class Response
      attr_reader :content, :tool_calls, :raw_response

      def initialize(content:, tool_calls: [], raw_response: nil)
        @content = content
        @tool_calls = tool_calls || []
        @raw_response = raw_response
      end

      def tool_calls?
        @tool_calls.any?
      end
    end
  end
end