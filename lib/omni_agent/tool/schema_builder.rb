module OmniAgent
  class Tool
    class SchemaBuilder
      attr_reader :properties, :required_fields

      def initialize
        @properties = {}
        @required_fields = []
      end

      def string(name, description: nil, required: true)
        add_property(name, type: "string", description: description, required: required)
      end

      def integer(name, description: nil, required: true)
        add_property(name, type: "integer", description: description, required: required)
      end

      def boolean(name, description: nil, required: true)
        add_property(name, type: "boolean", description: description, required: required)
      end

      def array(name, items_type: nil, description: nil, required: true, &block)
        property = { type: "array" }
        property[:description] = description if description

        if block_given?
          nested_builder = SchemaBuilder.new
          nested_builder.instance_eval(&block)

          property[:items] = {
            type: "object",
            properties: nested_builder.properties,
            required: nested_builder.required_fields,
            additionalProperties: false
          }
        else
          property[:items] = { type: items_type || "string" }
        end

        @properties[name] = property
        @required_fields << name.to_s if required
      end

      def hash(name, description: nil, required: true, &block)
        property = { type: "object" }
        property[:description] = description if description

        if block_given?
          nested_builder = SchemaBuilder.new
          nested_builder.instance_eval(&block)

          property[:properties] = nested_builder.properties
          property[:required] = nested_builder.required_fields
          property[:additionalProperties] = false
        else
          property[:additionalProperties] = true
        end

        @properties[name] = property
        @required_fields << name.to_s if required
      end

      def enum(name, values:, description: nil, required: true)
        raise ArgumentError, "enum requires at least one value" if values.empty?

        normalized_values = values.map { |v| v.is_a?(Symbol) ? v.to_s : v }
        value_data_type = enum_data_type(normalized_values)

        property = { type: value_data_type, enum: normalized_values }
        property[:description] = description if description
        @properties[name] = property
        @required_fields << name.to_s if required
      end

      private

      def enum_data_type(values)
        types = values.map { |v| json_type_for(v) }.uniq

        if types.size > 1
          raise ArgumentError, "enum values must all be the same type, got: #{types.join(', ')}"
        end

        types.first
      end

      def json_type_for(value)
        case value
        when Integer then "integer"
        when Float then "number"
        when String then "string"
        when true, false then "boolean"
        else
          raise ArgumentError, "unsupported enum value type: #{value.class}"
        end
      end

      def add_property(name, type:, description:, required:)
        property = { type: type }
        property[:description] = description if description

        @properties[name] = property
        @required_fields << name.to_s if required
      end
    end
  end
end
