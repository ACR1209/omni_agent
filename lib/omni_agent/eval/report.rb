module OmniAgent
  class Eval
    class Report
      attr_reader :case_results

      def initialize(case_results)
        @case_results = case_results
      end

      def passed?
        case_results.all?(&:passed?)
      end

      def raise_on_failure!
        return if passed?

        failures = case_results.reject(&:passed?).map(&:case_name)
        raise OmniAgent::EvalAssertionError, "Eval cases failed: #{failures.join(', ')}"
      end

      def print(io: $stdout)
        case_results.each do |case_result|
          status = case_result.passed? ? "PASS" : "FAIL"
          io.puts "[#{status}] #{case_result.case_name}"

          case_result.outcomes.each do |outcome|
            next if outcome.passed?
            io.puts "  - #{outcome.message}"
          end
        end

        passed_count = case_results.count(&:passed?)
        io.puts "\n#{passed_count}/#{case_results.size} cases passed"
      end
    end
  end
end
