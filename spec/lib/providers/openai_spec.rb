require_relative "../../spec_helper"
require_relative "../../../lib/omni_agent/errors"
require_relative "../../../lib/omni_agent/providers/base"
require_relative "../../../lib/omni_agent/providers/response"
require_relative "../../../lib/omni_agent/providers/openai"
require_relative "../../../lib/omni_agent/tool/schema_builder"
require_relative "../../../lib/omni_agent/tool"

RSpec.describe OmniAgent::Providers::OpenAI do
  it "sends the expected payload to the client and parses the response" do
    messages = [{ role: "user", content: "Hello" }]
    raw_response = {
      "choices" => [
        { "message" => { "content" => "Hi there" } }
      ]
    }

    client_instance = instance_double(OpenAI::Client)
    allow(OpenAI::Client).to receive(:new)
      .with(access_token: "token")
      .and_return(client_instance)
    expect(client_instance).to receive(:chat)
      .with(parameters: { model: "gpt-test", messages: messages })
      .and_return(raw_response)

    result = described_class.new(api_key: "token", model: "gpt-test").chat(messages: messages)

    expect(result).to be_a(OmniAgent::Providers::Response)
    expect(result.content).to eq("Hi there")
    expect(result.raw_response).to eq(raw_response)
  end

  it "uses gpt-4o as the default model" do
    provider = described_class.new(api_key: "token")

    expect(provider.model).to eq("gpt-4o")
  end

  describe "integration tests" do
    before do
      module ResearchAgent
        module Tools
        end
      end

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

      stub_const("ResearchAgent::Tools::WebSearch", web_search_class)
    end    

    it "formats tools correctly in the payload" do
      provider = described_class.new(api_key: "token", model: "gpt-test")

      expected_tool_payload = [
        {
          type: "function",
          function: {
            name: "WebSearch",
            description: "Searches the web for current events, news, or factual data.",
            parameters: {
              type: "object",
              properties: {
                query: { type: "string", description: "The precise search query to execute" },
                limit: { type: "integer", description: "Maximum number of results to return" },
                safe_search: { type: "boolean", description: "Whether to filter explicit content" }
              },
              required: ["query"],
              additionalProperties: false
            }
          }
        }
      ]

      expect(provider).to receive(:client).and_return(double(chat: {}))
      expect(provider).to receive(:format_tool).with(ResearchAgent::Tools::WebSearch).and_call_original

      provider.chat(messages: [{ role: "user", content: "Search the web" }], tools: [ResearchAgent::Tools::WebSearch])
    end
  end
end
