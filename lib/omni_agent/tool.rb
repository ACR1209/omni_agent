module OmniAgent
  class Tool
    class << self
      def description(text = nil)
        @description = text if text
        @description || "No description provided."
      end

      def metadata(options = nil)
        @metadata = options if options
        @metadata || {}
      end

      def tags(*tag_names)
        return @tags || [] if tag_names.empty?

        @tags = (tags + normalize_tags(tag_names)).uniq
      end

      def configured_tags
        tags
      end

      def input(&block)
        if block_given?
          builder = SchemaBuilder.new
          builder.instance_eval(&block)

          @properties = builder.properties
          @required = builder.required_fields
          @validators = builder.validators
          @polymorphics = builder.polymorphics
        end
      end

      def json_schema
        {
          type: "object",
          properties: @properties || {},
          required: @required || [],
          additionalProperties: false
        }
      end

      def parse_arguments(arguments_hash)
        kwargs = arguments_hash.transform_keys(&:to_sym)
        valid_keys = (@properties || {}).keys.map(&:to_sym)
        filtered = kwargs.slice(*valid_keys)

        validate_required!(filtered)
        validate_enums!(filtered)
        validate_constraints!(filtered)
        run_custom_validators!(filtered)
        resolve_polymorphics!(filtered)

        filtered
      end

      def stops_generation(value = true)
        @stops_generation = !!value
      end

      def stops_generation?
        @stops_generation == true
      end

      private

      def validate_required!(kwargs)
        missing = (@required || []).map(&:to_sym) - kwargs.keys
        return if missing.empty?

        raise ArgumentError, "missing required argument(s): #{missing.join(', ')}"
      end

      def validate_enums!(kwargs)
        (@properties || {}).each do |name, property|
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
        (@properties || {}).each do |name, property|
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
        (@validators || {}).each do |name, validator|
          key = name.to_sym
          next unless kwargs.key?(key)

          result = validator.call(kwargs[key])
          raise ArgumentError, "invalid value for #{name}" if result == false
        end
      end

      def resolve_polymorphics!(kwargs)
        (@polymorphics || {}).each do |name, group|
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

      def normalize_tags(tag_names)
        raise ArgumentError, "tags requires at least one tag" if tag_names.empty?

        tag_names.map do |tag_name|
          unless tag_name.is_a?(String) || tag_name.is_a?(Symbol)
            raise ArgumentError, "tags must be strings or symbols"
          end

          tag_name.to_sym
        end
      end
    end

    attr_accessor :context

    def initialize
      @context = {}
    end

    def invoke(arguments_hash)
      filtered_kwargs = self.class.parse_arguments(arguments_hash)
      execute(**filtered_kwargs)
    end

    def stop_generation!
      @stops_generation_instance = true
    end

    def stops_generation?
      @stops_generation_instance == true
    end

    def execute(**args)
      raise NotImplementedError, "#{self.class.name} must implement #execute"
    end
  end
end
