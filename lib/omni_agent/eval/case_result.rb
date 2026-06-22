module OmniAgent
  class Eval
    class CaseResult
      attr_reader :case_name, :outcomes

      def initialize(case_name:, outcomes:)
        @case_name = case_name
        @outcomes = outcomes
      end

      def passed?
        outcomes.all?(&:passed?)
      end
    end
  end
end
