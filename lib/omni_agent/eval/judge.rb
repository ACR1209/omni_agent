require "json"

module OmniAgent
  class Eval
    class Judge
      GRADING_PROMPT = <<~PROMPT
        You are grading an AI agent's output against a single criterion.

        Output: %<output>s

        Criterion: %<criteria>s

        Respond with strict JSON only, no other text: {"score": <float between 0 and 1>, "reason": "<short explanation>"}
      PROMPT

      def initialize(provider: nil, model: nil)
        @provider = provider
        @model = model
      end

      def call(criteria:, output:, fallback_provider: nil)
        judge_provider = resolve_provider(fallback_provider)
        prompt = format(GRADING_PROMPT, output: output, criteria: criteria)

        response = judge_provider.chat(messages: [ { role: "user", content: prompt } ])
        parse_score(response.content)
      end

      private

      def resolve_provider(fallback_provider)
        return @provider if @provider.is_a?(OmniAgent::Providers::Base)

        provider_name = @provider || OmniAgent.configuration.eval_judge_provider
        return fallback_provider if provider_name.nil?

        provider_class = OmniAgent::Providers.registry[provider_name.to_sym]
        unless provider_class
          raise OmniAgent::UnknownProviderError, "Unknown judge provider #{provider_name.inspect}"
        end

        provider_class.new(model: @model || OmniAgent.configuration.eval_judge_model)
      end

      def parse_score(content)
        data = JSON.parse(content.to_s)
        { score: data["score"].to_f, reason: data["reason"] }
      rescue JSON::ParserError
        { score: 0.0, reason: "judge response was not valid JSON: #{content.inspect}" }
      end
    end
  end
end
