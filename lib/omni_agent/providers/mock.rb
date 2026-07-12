module OmniAgent
  module Providers
    class Mock < Base
      LOREM_IPSUM = "Lorem ipsum dolor sit amet, consectetur adipiscing elit."

      def chat(messages:, tools: [], stream: nil, **_options)
        validate_messages!(messages, allowed_roles: %i[system user assistant tool])

        if stream
          LOREM_IPSUM.split(" ").each_with_index do |word, index|
            chunk = index.zero? ? word : " #{word}"
            stream.call(OmniAgent::Streaming::Event.text(chunk))
          end
        end

        OmniAgent::Providers::Response.new(
          content: LOREM_IPSUM,
          raw_request: {
            model: model,
            messages: messages,
            tools: tools
          },
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
