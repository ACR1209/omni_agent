require "json"

module OmniAgent
  module Providers
    class Mock < Base
      LOREM_IPSUM = "Lorem ipsum dolor sit amet, consectetur adipiscing elit."

      def chat(messages:, tools: [], stream: nil, output_schema: nil, **_options)
        validate_messages!(messages, allowed_roles: %i[system user assistant tool])

        content = output_schema ? JSON.generate(sample_object(output_schema.json_schema)) : LOREM_IPSUM

        if stream
          content.split(" ").each_with_index do |word, index|
            chunk = index.zero? ? word : " #{word}"
            stream.call(OmniAgent::Streaming::Event.text(chunk))
          end
        end

        OmniAgent::Providers::Response.new(
          content: content,
          raw_request: {
            model: model,
            messages: messages,
            tools: tools
          },
          raw_response: {
            "choices" => [
              {
                "message" => {
                  "content" => content
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

      private

      # Builds a placeholder value for every property so agents with an output
      # schema get a parseable, valid response without calling a real model.
      def sample_object(schema)
        (schema[:properties] || {}).to_h { |name, property| [ name, sample_value(property) ] }
      end

      def sample_value(property)
        return property[:enum].first if property[:enum]

        case property[:type]
        when "string" then sample_string(property)
        when "integer" then (property[:minimum] || 0).ceil
        when "number" then property[:minimum] || 0.0
        when "boolean" then true
        when "array" then Array.new([ property[:minItems].to_i, 1 ].max) { sample_value(property[:items] || {}) }
        when "object" then sample_object(property)
        end
      end

      def sample_string(property)
        text = LOREM_IPSUM
        text = text.ljust(property[:minLength], "x") if property[:minLength]
        text = text[0, property[:maxLength]] if property[:maxLength]
        text
      end
    end
  end
end
