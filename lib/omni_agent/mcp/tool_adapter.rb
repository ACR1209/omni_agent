require "json"

module OmniAgent
  module MCP
    module ToolAdapter
      module_function

      def definition(name, tool_class)
        definition = { name: name }
        definition[:title] = tool_class.title if tool_class.title
        definition[:description] = tool_class.description
        definition[:inputSchema] = tool_class.json_schema

        annotations = tool_class.mcp_annotations
        definition[:annotations] = annotations unless annotations.empty?

        definition
      end

      def result(value)
        case value
        when nil
          { content: [ text_content("") ] }
        when String
          { content: [ text_content(value) ] }
        when Hash
          json = JSON.generate(value)
          { content: [ text_content(json) ], structuredContent: JSON.parse(json) }
        when Array
          { content: [ text_content(JSON.generate(value)) ] }
        else
          { content: [ text_content(value.to_s) ] }
        end
      end

      def error_result(message)
        { content: [ text_content(message) ], isError: true }
      end

      def text_content(text)
        { type: "text", text: text }
      end
    end
  end
end
