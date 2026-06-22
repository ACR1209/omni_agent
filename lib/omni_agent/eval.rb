module OmniAgent
  class Eval
    class << self
      def agent(klass = nil)
        @agent_class = klass if klass
        @agent_class
      end

      def eval_case(name, &block)
        @configured_cases = configured_cases + [ Case.new(name, &block) ]
      end

      def golden_set(path, &block)
        new_cases = GoldenSet.load(path).each_with_index.map do |row, index|
          case_name = row[:name] || "row #{index}"
          Case.new(case_name, input: row[:input], context: row[:context] || {}, run_alias: row[:run_alias], row: row, &block)
        end

        @configured_cases = configured_cases + new_cases
      end

      def configured_agent
        @agent_class
      end

      def configured_cases
        @configured_cases || []
      end

      def run_all
        unless configured_agent
          raise OmniAgent::Error, "#{name} must declare `agent SomeAgentClass` before running evals"
        end

        case_results = configured_cases.map { |eval_case| Runner.run(eval_case, configured_agent) }
        Report.new(case_results)
      end
    end
  end
end
