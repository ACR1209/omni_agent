require_relative "../../spec_helper"
require_relative "../../../lib/omni_agent/tool/schema_builder"
require_relative "../../../lib/omni_agent/tool"

RSpec.describe "Tool integration with a concrete class" do
  before do
    stub_const("ToolSpecAgent", Module.new)
    stub_const("ToolSpecAgent::Tools", Module.new)

    web_search_class = Class.new(OmniAgent::Tool) do
      description "Searches the web for current events, news, or factual data."

      metadata category: :research, requires_auth: false

      input do
        string :query, description: "The precise search query to execute"
        integer :limit, description: "Maximum number of results to return", required: false
        boolean :safe_search, description: "Whether to filter explicit content", required: false
      end

      def execute(query:, limit: 5, safe_search: true)
        puts "Searching for #{query} (limit: #{limit}, safe: #{safe_search})..."
        "Found 3 articles about #{query}..."
      end
    end

    stub_const("ToolSpecAgent::Tools::WebSearch", web_search_class)
  end

  it "wires class metadata, schema, and execution together" do
    expect(ToolSpecAgent::Tools::WebSearch.description)
      .to eq("Searches the web for current events, news, or factual data.")

    expect(ToolSpecAgent::Tools::WebSearch.metadata)
      .to eq(category: :research, requires_auth: false)

    expect(ToolSpecAgent::Tools::WebSearch.json_schema).to eq(
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "The precise search query to execute"
        },
        limit: {
          type: "integer",
          description: "Maximum number of results to return"
        },
        safe_search: {
          type: "boolean",
          description: "Whether to filter explicit content"
        }
      },
      required: [ "query" ],
      additionalProperties: false
    )

    expect do
      result = ToolSpecAgent::Tools::WebSearch.new.invoke("query" => "AI safety")
      expect(result).to eq("Found 3 articles about AI safety...")
    end.to output("Searching for AI safety (limit: 5, safe: true)...\n").to_stdout
  end
end
