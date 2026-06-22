module OmniAgent
  module Providers
    class MockJudge < Base
      CANNED_SCORE = 1.0
      CANNED_REASON = "mock judge always approves"

      def chat(messages:, tools: [], **_options)
        validate_messages!(messages, allowed_roles: %i[system user assistant tool])

        content = { score: CANNED_SCORE, reason: CANNED_REASON }.to_json

        OmniAgent::Providers::Response.new(
          content: content,
          raw_request: { model: model, messages: messages, tools: tools },
          raw_response: { "choices" => [ { "message" => { "content" => content } } ] },
          tool_calls: []
        )
      end

      protected

      def default_api_key
        nil
      end

      def default_model
        "mock-judge"
      end
    end
  end
end
