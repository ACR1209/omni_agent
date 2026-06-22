module OmniAgent
  class Eval
    class Outcome
      attr_reader :message, :score

      def initialize(passed:, message:, score: nil)
        @passed = passed
        @message = message
        @score = score
      end

      def passed?
        @passed == true
      end
    end
  end
end
