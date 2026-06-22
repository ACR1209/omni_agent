module OmniAgent
  class Eval
    class OutputAssertion
      def initialize(to_include: nil, to_match: nil, &block)
        @to_include = to_include
        @to_match = to_match
        @block = block
      end

      def call(run)
        output = run.output

        return call_block(output) if @block
        return call_to_include(output) if @to_include
        return call_to_match(output) if @to_match

        raise ArgumentError, "expect_output requires to_include:, to_match:, or a block"
      end

      private

      def call_block(output)
        passed = !!@block.call(output)
        message = passed ? "output matched custom block" : "output #{output.inspect} failed custom block"
        Outcome.new(passed: passed, message: message)
      end

      def call_to_include(output)
        passed = output.to_s.include?(@to_include.to_s)
        message = passed ? "output includes #{@to_include.inspect}" : "output #{output.inspect} does not include #{@to_include.inspect}"
        Outcome.new(passed: passed, message: message)
      end

      def call_to_match(output)
        passed = !!(output.to_s =~ @to_match)
        message = passed ? "output matches #{@to_match.inspect}" : "output #{output.inspect} does not match #{@to_match.inspect}"
        Outcome.new(passed: passed, message: message)
      end
    end
  end
end
