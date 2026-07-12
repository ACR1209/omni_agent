module OmniAgent
  module Streaming
    class Event
      attr_reader :type, :text, :tool_name, :tool_arguments, :tool_id, :content, :error, :response

      def self.text(delta)
        new(type: :text, text: delta)
      end

      def self.tool_call(name:, arguments:, id:)
        new(type: :tool_call, tool_name: name, tool_arguments: arguments, tool_id: id)
      end

      def self.tool_result(name:, id:, content:, error: false)
        new(type: :tool_result, tool_name: name, tool_id: id, content: content, error: error)
      end

      def self.done(response)
        new(type: :done, response: response)
      end

      def initialize(type:, text: nil, tool_name: nil, tool_arguments: nil, tool_id: nil, content: nil, error: false, response: nil)
        @type = type
        @text = text
        @tool_name = tool_name
        @tool_arguments = tool_arguments
        @tool_id = tool_id
        @content = content
        @error = error
        @response = response
      end

      def text?
        type == :text
      end

      def tool_call?
        type == :tool_call
      end

      def tool_result?
        type == :tool_result
      end

      def done?
        type == :done
      end

      def error?
        @error == true
      end
    end
  end
end
