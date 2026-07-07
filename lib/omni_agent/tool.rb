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
        kwargs.slice(*valid_keys)
      end

      def stops_generation(value = true)
        @stops_generation = !!value
      end

      def stops_generation?
        @stops_generation == true
      end

      private

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
