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

      def array(name, items_type:, description: nil, required: true)
        property = { type: "array", items: { type: items_type } }
        property[:description] = description if description
        
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

      private

      def add_property(name, type:, description:, required:)
        property = { type: type }
        property[:description] = description if description
        
        @properties[name] = property
        @required_fields << name.to_s if required
      end
    end
  end
end