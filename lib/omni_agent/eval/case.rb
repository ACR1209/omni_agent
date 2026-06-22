module OmniAgent
  class Eval
    class Case
      attr_reader :name

      def initialize(name, input: nil, context: {}, run_alias: nil, row: nil, &block)
        @name = name
        @input = input
        @context = context || {}
        @run_alias = run_alias
        @assertions = []

        if block
          row.nil? ? instance_eval(&block) : instance_exec(row, &block)
        end
      end

      def input(text, with: {})
        @input = text
        @context = with || {}
      end

      def run_alias(name)
        @run_alias = name
      end

      def expect_tool_call(tool_name, with: nil)
        @assertions << ToolCallAssertion.new(tool_name, with: with)
      end

      def expect_output(to_include: nil, to_match: nil, &block)
        @assertions << OutputAssertion.new(to_include: to_include, to_match: to_match, &block)
      end

      def judge(criteria, threshold: 0.7, provider: nil, model: nil)
        @assertions << JudgeAssertion.new(criteria, threshold: threshold, provider: provider, model: model)
      end

      def configured_input
        @input
      end

      def configured_context
        @context
      end

      def configured_run_alias
        @run_alias
      end

      def configured_assertions
        @assertions
      end
    end
  end
end
