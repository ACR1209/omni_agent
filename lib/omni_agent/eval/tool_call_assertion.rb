module OmniAgent
  class Eval
    class ToolCallAssertion
      def initialize(tool_name, with: nil)
        @tool_name = tool_name.to_s
        @expected_args = with
      end

      def call(run)
        matches = run.tool_calls.select { |tool_call| tool_call[:name] == @tool_name }

        if matches.empty?
          return Outcome.new(passed: false, message: "expected tool `#{@tool_name}` to be called, but it wasn't")
        end

        return Outcome.new(passed: true, message: "tool `#{@tool_name}` was called") if @expected_args.nil?

        expected = @expected_args.transform_keys(&:to_sym)
        if matches.any? { |tool_call| expected.all? { |key, value| tool_call[:arguments][key] == value } }
          Outcome.new(passed: true, message: "tool `#{@tool_name}` was called with #{expected}")
        else
          got = matches.map { |tool_call| tool_call[:arguments] }
          Outcome.new(passed: false, message: "tool `#{@tool_name}` was called, but not with #{expected} (got #{got})")
        end
      end
    end
  end
end
