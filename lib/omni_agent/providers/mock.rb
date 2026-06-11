module OmniAgent
  module Providers
    class Mock < Base
      LOREM_IPSUM = "Lorem ipsum dolor sit amet, consectetur adipiscing elit."

      def chat(messages:, tools: [], **_options)
        validate_messages!(messages, allowed_roles: %i[system user assistant tool])

        OmniAgent::Providers::Response.new(
          content: LOREM_IPSUM,
          raw_response: {
            "choices" => [
              {
                "message" => {
                  "content" => LOREM_IPSUM
                }
              }
            ]
          },
          tool_calls: []
        )
      end

      protected

      def default_api_key
        nil
      end

      def default_model
        "mock"
      end
    end
  end
end
