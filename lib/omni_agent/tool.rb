# lib/omni_agents/tool.rb
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

      def invoke(arguments_hash)
        kwargs = arguments_hash.transform_keys(&:to_sym)
        new.execute(**kwargs)
      end
    end

    def execute(**args)
      raise NotImplementedError, "#{self.class.name} must implement #execute"
    end
  end
end