module OmniAgent
  class Eval
    class Run
      attr_reader :output, :tool_calls, :agent

      def initialize(output:, tool_calls:, agent:)
        @output = output
        @tool_calls = tool_calls
        @agent = agent
      end
    end
  end
end
