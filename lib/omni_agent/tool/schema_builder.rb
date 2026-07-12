module OmniAgent
  class Tool
    class SchemaBuilder
      attr_reader :properties, :required_fields, :validators, :polymorphics

      def initialize
        @properties = {}
        @required_fields = []
        @validators = {}
        @polymorphics = {}
      end

      def string(name, description: nil, required: true, min_length: nil, max_length: nil, pattern: nil, format: nil, validate: nil)
        constraints = {}
        constraints[:minLength] = min_length if min_length
        constraints[:maxLength] = max_length if max_length
        constraints[:pattern] = pattern.is_a?(Regexp) ? pattern.source : pattern if pattern
        constraints[:format] = format if format

        add_property(name, type: "string", description: description, required: required, constraints: constraints, validate: validate)
      end

      def integer(name, description: nil, required: true, min: nil, max: nil, validate: nil)
        constraints = {}
        constraints[:minimum] = min if min
        constraints[:maximum] = max if max

        add_property(name, type: "integer", description: description, required: required, constraints: constraints, validate: validate)
      end

      def number(name, description: nil, required: true, min: nil, max: nil, validate: nil)
        constraints = {}
        constraints[:minimum] = min if min
        constraints[:maximum] = max if max

        add_property(name, type: "number", description: description, required: required, constraints: constraints, validate: validate)
      end

      def boolean(name, description: nil, required: true, validate: nil)
        add_property(name, type: "boolean", description: description, required: required, validate: validate)
      end

      def array(name, items_type: nil, description: nil, required: true, min_items: nil, max_items: nil, validate: nil, &block)
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

        property[:minItems] = min_items if min_items
        property[:maxItems] = max_items if max_items

        @properties[name] = property
        @required_fields << name.to_s if required
        @validators[name] = validate if validate
      end

      def hash(name, description: nil, required: true, validate: nil, &block)
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
        @validators[name] = validate if validate
      end

      def enum(name, values:, description: nil, required: true, validate: nil)
        raise ArgumentError, "enum requires at least one value" if values.empty?

        normalized_values = values.map { |v| v.is_a?(Symbol) ? v.to_s : v }
        value_data_type = enum_data_type(normalized_values)

        property = { type: value_data_type, enum: normalized_values }
        property[:description] = description if description
        @properties[name] = property
        @required_fields << name.to_s if required
        @validators[name] = validate if validate
      end

      def polymorphic(name, types: nil, description: nil, id_type: "string", required: true, resolve: false, &block)
        if resolve && (types.nil? || types.empty?)
          raise ArgumentError, "polymorphic resolve: true requires types:"
        end

        type_values = types
        type_description = description ? "#{description} (type)" : nil
        id_type_value = id_type
        id_description = description ? "#{description} (id)" : nil

        if block_given?
          field_builder = PolymorphicFieldBuilder.new
          field_builder.instance_eval(&block)

          type_values = field_builder.type_values || type_values
          type_description = field_builder.type_description || type_description
          id_type_value = field_builder.id_type || id_type_value
          id_description = field_builder.id_description || id_description
        end

        type_field = :"#{name}_type"
        id_field = :"#{name}_id"
        id_json_type = id_type_value.to_s == "integer" ? "integer" : "string"

        if type_values && !type_values.empty?
          enum(type_field, values: type_values, description: type_description, required: required)
        else
          string(type_field, description: type_description, required: required)
        end

        if id_json_type == "integer"
          integer(id_field, description: id_description, required: required)
        else
          string(id_field, description: id_description, required: required)
        end

        @polymorphics[name] = {
          type_field: type_field,
          id_field: id_field,
          types: type_values,
          id_type: id_json_type,
          resolve: resolve
        }
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

      def add_property(name, type:, description:, required:, constraints: {}, validate: nil)
        property = { type: type }
        property[:description] = description if description
        property.merge!(constraints)

        @properties[name] = property
        @required_fields << name.to_s if required
        @validators[name] = validate if validate
      end

      class PolymorphicFieldBuilder
        attr_reader :type_values, :type_description, :id_type, :id_description

        def type(values: nil, description: nil)
          @type_values = values
          @type_description = description
        end

        def id(type: "string", description: nil)
          @id_type = type
          @id_description = description
        end
      end
    end
  end
end
