module OmniAgent
  class Eval
    class JudgeAssertion
      def initialize(criteria, threshold: 0.7, provider: nil, model: nil)
        @criteria = criteria
        @threshold = threshold
        @judge = Judge.new(provider: provider, model: model)
      end

      def call(run)
        verdict = @judge.call(criteria: @criteria, output: run.output, fallback_provider: run.agent.provider)
        passed = verdict[:score] >= @threshold

        Outcome.new(
          passed: passed,
          message: "judge score #{verdict[:score]} (threshold #{@threshold}) - #{verdict[:reason]}",
          score: verdict[:score]
        )
      end
    end
  end
end
