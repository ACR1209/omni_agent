require "rails/generators/named_base"
require "fileutils"

module OmniAgent
  module Generators
    class StockAgentGenerator < Rails::Generators::NamedBase
      FIELD_TYPES = %w[string integer number boolean].freeze

      class_option :from,
                   type: :string,
                   required: true,
                   desc: "Stock agent to build on (e.g. ocr)"
      class_option :fields,
                   type: :array,
                   default: [],
                   banner: "name:type name:type ...",
                   desc: "Output fields to declare (types: #{FIELD_TYPES.join(', ')})"

      def create_agent_structure
        agent_source = [
          "class #{class_name} < #{stock_agent_class.name}",
          "  output do",
          *output_field_lines.map { |line| "    #{line}" },
          "  end",
          "end"
        ].join("\n")

        FileUtils.mkdir_p(agent_directory)
        create_file(agent_file_path, "#{agent_source}\n")

        create_file(prompt_file_path, <<~ERB)
          <%# Optional: extra instructions appended after the #{stock_agent_class.stock_name} stock agent prompt. %>
        ERB
      end

      private

      def stock_agent_class
        @stock_agent_class ||= OmniAgent::StockAgents.find(options[:from])
      rescue OmniAgent::UnknownStockAgentError => e
        raise Thor::Error, e.message
      end

      def output_field_lines
        fields = Array(options[:fields]).map(&:strip).reject(&:empty?)
        return [ 'string :example_field, description: "Describe the value the agent must return"' ] if fields.empty?

        fields.map do |field|
          name, type = field.split(":", 2)
          type = (type || "string").downcase

          unless FIELD_TYPES.include?(type)
            raise Thor::Error, "Unsupported field type #{type.inspect} for #{name}. Use one of: #{FIELD_TYPES.join(', ')}"
          end

          "#{type} :#{name.underscore}"
        end
      end

      def agent_directory
        File.join(destination_root, "app", "agents", file_name)
      end

      def agent_file_path
        File.join(destination_root, "app", "agents", "#{file_name}.rb")
      end

      def prompt_file_path
        File.join(agent_directory, "prompt.md.erb")
      end
    end
  end
end
