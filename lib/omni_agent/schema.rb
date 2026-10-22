module OmniAgent
  # A typed object schema declared with the Tool::SchemaBuilder DSL. Tools use
  # it to describe and validate their input; agents use it to describe and
  # validate their structured output.
  class Schema
    STRICT_UNSUPPORTED_KEYWORDS = %i[minLength maxLength].freeze

    attr_reader :properties, :required, :validators, :polymorphics

    def self.build(&block)
      builder = Tool::SchemaBuilder.new
      builder.instance_eval(&block)

      new(
        properties: builder.properties,
        required: builder.required_fields,
        validators: builder.validators,
        polymorphics: builder.polymorphics
      )
    end

    def initialize(properties: {}, required: [], validators: {}, polymorphics: {})
      @properties = properties
      @required = required
      @validators = validators
      @polymorphics = polymorphics
    end

    def json_schema
      {
        type: "object",
        properties: properties,
        required: required,
        additionalProperties: false
      }
    end

    # Whether the schema satisfies the constraints of strict structured-output
    # modes (e.g. OpenAI's `strict: true`): every property required, no
    # free-form objects, and no keywords those modes reject.
    def strict_compatible?
      strict_object?(json_schema)
    end

    # Filters unknown keys, validates the rest, and returns a symbol-keyed hash.
    # Raises ArgumentError when validation fails.
    def parse(values)
      raise ArgumentError, "expected an object, got #{values.class}" unless values.is_a?(Hash)

      kwargs = values.transform_keys(&:to_sym)
      valid_keys = properties.keys.map(&:to_sym)
      filtered = kwargs.slice(*valid_keys)

      validate_required!(filtered)
      validate_enums!(filtered)
      validate_constraints!(filtered)
      run_custom_validators!(filtered)
      resolve_polymorphics!(filtered)

      filtered
    end

    private

    def strict_object?(schema)
      return false unless schema[:additionalProperties] == false

      nested = schema[:properties] || {}
      return false unless nested.keys.map(&:to_s).sort == Array(schema[:required]).map(&:to_s).sort

      nested.values.all? { |property| strict_property?(property) }
    end

    def strict_property?(property)
      return false if STRICT_UNSUPPORTED_KEYWORDS.any? { |keyword| property.key?(keyword) }

      case property[:type]
      when "object" then strict_object?(property)
      when "array" then strict_property?(property[:items] || {})
      else true
      end
    end

    def validate_required!(kwargs)
      missing = required.map(&:to_sym) - kwargs.keys
      return if missing.empty?

      raise ArgumentError, "missing required argument(s): #{missing.join(', ')}"
    end

    def validate_enums!(kwargs)
      properties.each do |name, property|
        allowed_values = property[:enum]
        next unless allowed_values

        key = name.to_sym
        next unless kwargs.key?(key)

        unless allowed_values.include?(kwargs[key])
          raise ArgumentError, "invalid value for #{name}: #{kwargs[key].inspect} (must be one of: #{allowed_values.join(', ')})"
        end
      end
    end

    def validate_constraints!(kwargs)
      properties.each do |name, property|
        key = name.to_sym
        next unless kwargs.key?(key)

        check_constraints!(name, property, kwargs[key])
      end
    end

    def check_constraints!(name, property, value)
      if property[:minLength] && value.is_a?(String) && value.length < property[:minLength]
        raise ArgumentError, "#{name} must be at least #{property[:minLength]} characters"
      end
      if property[:maxLength] && value.is_a?(String) && value.length > property[:maxLength]
        raise ArgumentError, "#{name} must be at most #{property[:maxLength]} characters"
      end
      if property[:pattern] && value.is_a?(String) && !value.match?(Regexp.new(property[:pattern]))
        raise ArgumentError, "#{name} does not match required pattern #{property[:pattern]}"
      end
      if property[:minimum] && value.is_a?(Numeric) && value < property[:minimum]
        raise ArgumentError, "#{name} must be >= #{property[:minimum]}"
      end
      if property[:maximum] && value.is_a?(Numeric) && value > property[:maximum]
        raise ArgumentError, "#{name} must be <= #{property[:maximum]}"
      end
      if property[:minItems] && value.is_a?(Array) && value.length < property[:minItems]
        raise ArgumentError, "#{name} must have at least #{property[:minItems]} items"
      end
      if property[:maxItems] && value.is_a?(Array) && value.length > property[:maxItems]
        raise ArgumentError, "#{name} must have at most #{property[:maxItems]} items"
      end
    end

    def run_custom_validators!(kwargs)
      validators.each do |name, validator|
        key = name.to_sym
        next unless kwargs.key?(key)

        result = validator.call(kwargs[key])
        raise ArgumentError, "invalid value for #{name}" if result == false
      end
    end

    def resolve_polymorphics!(kwargs)
      polymorphics.each do |name, group|
        next unless group[:resolve]

        type_field = group[:type_field]
        id_field = group[:id_field]
        next unless kwargs.key?(type_field) && kwargs.key?(id_field)

        type_value = kwargs.delete(type_field)
        id_value = kwargs.delete(id_field)

        klass = Object.const_get(type_value.to_s)
        record = klass.find(id_value)
        kwargs[name.to_sym] = record
      end
    end
  end
end
