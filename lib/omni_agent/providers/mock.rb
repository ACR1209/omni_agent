require "json"

module OmniAgent
  module Providers
    class Mock < Base
      LOREM_IPSUM = "Lorem ipsum dolor sit amet, consectetur adipiscing elit."

      def chat(messages:, tools: [], stream: nil, output_schema: nil, **_options)
        validate_messages!(messages, allowed_roles: %i[system user assistant tool])

        content = output_schema ? JSON.generate(sample_output(output_schema)) : LOREM_IPSUM

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

      def supports_structured_output?
        true
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
      # schema get a parseable response without calling a real model. Raises
      # when a field needs a value the mock can't invent (pattern, custom
      # validate:, polymorphic resolve: true).
      def sample_output(output_schema)
        unresolvable = output_schema.polymorphics.find { |_name, group| group[:resolve] }
        unsatisfiable!(unresolvable.first, "it is polymorphic with resolve: true") if unresolvable

        sample = sample_object(output_schema.json_schema)

        output_schema.validators.each do |name, validator|
          passed = begin
            validator.call(sample[name]) != false
          rescue StandardError
            false
          end
          unsatisfiable!(name, "its validate: proc rejects the placeholder #{sample[name].inspect}") unless passed
        end

        sample
      end

      def sample_object(schema, path = nil)
        (schema[:properties] || {}).to_h do |name, property|
          [ name, sample_value(property, [ path, name ].compact.join(".")) ]
        end
      end

      def sample_value(property, path)
        return property[:enum].first if property[:enum]

        case property[:type]
        when "string" then sample_string(property, path)
        when "integer" then sample_number(property, integer: true)
        when "number" then sample_number(property).to_f
        when "boolean" then true
        when "array" then Array.new([ property[:minItems].to_i, 1 ].max) { sample_value(property[:items] || {}, "#{path}[]") }
        when "object" then sample_object(property, path)
        end
      end

      def sample_number(property, integer: false)
        minimum = property[:minimum]
        maximum = property[:maximum]
        return integer ? minimum.ceil : minimum if minimum
        return integer ? maximum.floor : maximum if maximum && maximum < 0

        0
      end

      def sample_string(property, path)
        text = LOREM_IPSUM
        text = text.ljust(property[:minLength], "x") if property[:minLength]
        text = text[0, property[:maxLength]] if property[:maxLength]

        if property[:pattern] && !text.match?(Regexp.new(property[:pattern]))
          unsatisfiable!(path, "its value must match the pattern #{property[:pattern]}")
        end

        text
      end

      def unsatisfiable!(field, reason)
        raise OmniAgent::Error,
              "The mock provider can't generate structured output for `#{field}` because #{reason}. " \
              "Stub the provider's #chat response in this test instead."
      end
    end
  end
end
