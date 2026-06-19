require_relative "../../spec_helper"
require "active_support"
require_relative "../../../lib/omni_agent"
require_relative "../../../lib/omni_agent/providers/base"
require_relative "../../../lib/omni_agent/providers/response"
require_relative "../../../lib/omni_agent/providers/openai"
require_relative "../../../lib/omni_agent/tool/schema_builder"
require_relative "../../../lib/omni_agent/tool"

RSpec.describe OmniAgent::Providers::OpenAI do
  it "sends the expected payload to the client and parses the response" do
    messages = [ { role: "user", content: "Hello" } ]
    raw_response = {
      "choices" => [
        { "message" => { "content" => "Hi there" } }
      ]
    }

    completions = double("completions")
    chat = double("chat", completions: completions)
    client_instance = instance_double(OpenAI::Client, chat: chat)
    allow(OpenAI::Client).to receive(:new)
      .with(api_key: "token")
      .and_return(client_instance)
    expect(completions).to receive(:create)
      .with(model: "gpt-test", messages: messages)
      .and_return(raw_response)

    result = described_class.new(api_key: "token", model: "gpt-test").chat(messages: messages)

    expect(result).to be_a(OmniAgent::Providers::Response)
    expect(result.content).to eq("Hi there")
    expect(result.raw_response).to eq(raw_response)
    expect(result.raw_request).to eq(model: "gpt-test", messages: messages)
  end

  it "uses gpt-4o-mini as the default model" do
    provider = described_class.new(api_key: "token")

    expect(provider.model).to eq("gpt-4o-mini")
  end

  it "forwards extra model options like temperature into the payload" do
    messages = [ { role: "user", content: "Hello" } ]

    completions = double("completions")
    chat = double("chat", completions: completions)
    client_instance = instance_double(OpenAI::Client, chat: chat)
    allow(OpenAI::Client).to receive(:new)
      .with(api_key: "token")
      .and_return(client_instance)
    expect(completions).to receive(:create)
      .with(model: "gpt-test", messages: messages, temperature: 0.3)
      .and_return({ "choices" => [ { "message" => { "content" => "Hi" } } ] })

    described_class.new(api_key: "token", model: "gpt-test").chat(messages: messages, temperature: 0.3)
  end

  it "raises when messages contain invalid roles" do
    provider = described_class.new(api_key: "token", model: "gpt-test")

    expect {
      provider.chat(messages: [ { role: "invalid", content: "Hello" } ])
    }.to raise_error(OmniAgent::Error, /invalid message role/)
  end

  it "preserves the full raw provider response" do
    messages = [ { role: "user", content: "Hello" } ]
    raw_response = {
      "id" => "chatcmpl_123",
      "object" => "chat.completion",
      "usage" => { "prompt_tokens" => 10, "completion_tokens" => 4, "total_tokens" => 14 },
      "choices" => [
        { "message" => { "content" => "Hi there" } }
      ]
    }

    completions = double("completions")
    chat = double("chat", completions: completions)
    client_instance = instance_double(OpenAI::Client, chat: chat)
    allow(OpenAI::Client).to receive(:new)
      .with(api_key: "token")
      .and_return(client_instance)
    expect(completions).to receive(:create)
      .with(model: "gpt-test", messages: messages)
      .and_return(raw_response)

    result = described_class.new(api_key: "token", model: "gpt-test").chat(messages: messages)

    expect(result.raw_response).to eq(raw_response)
    expect(result.raw_request).to eq(model: "gpt-test", messages: messages)
    expect(result.raw_response["usage"]).to eq({ "prompt_tokens" => 10, "completion_tokens" => 4, "total_tokens" => 14 })
  end

  describe "retry behavior" do
    before { allow_any_instance_of(described_class).to receive(:sleep) }

    it "retries on rate limit errors and succeeds" do
      messages = [ { role: "user", content: "Hello" } ]
      completions = double("completions")
      chat = double("chat", completions: completions)
      client_instance = instance_double(OpenAI::Client, chat: chat)
      allow(OpenAI::Client).to receive(:new).and_return(client_instance)

      rate_limit_error = OpenAI::Errors::RateLimitError.new(
        url: URI("https://api.openai.com"), status: 429, headers: {}, body: nil, request: nil, response: nil, message: "rate limited"
      )

      call_count = 0
      allow(completions).to receive(:create) do
        call_count += 1
        raise rate_limit_error if call_count < 3

        { "choices" => [ { "message" => { "content" => "Hi" } } ] }
      end

      result = described_class.new(api_key: "token", model: "gpt-test").chat(messages: messages)

      expect(call_count).to eq(3)
      expect(result.content).to eq("Hi")
    end

    it "gives up after max_retries and raises OmniAgent::Error" do
      OmniAgent.configuration.max_retries = 2
      messages = [ { role: "user", content: "Hello" } ]
      completions = double("completions")
      chat = double("chat", completions: completions)
      client_instance = instance_double(OpenAI::Client, chat: chat)
      allow(OpenAI::Client).to receive(:new).and_return(client_instance)

      rate_limit_error = OpenAI::Errors::RateLimitError.new(
        url: URI("https://api.openai.com"), status: 429, headers: {}, body: nil, request: nil, response: nil, message: "rate limited"
      )
      allow(completions).to receive(:create).and_raise(rate_limit_error)

      expect {
        described_class.new(api_key: "token", model: "gpt-test").chat(messages: messages)
      }.to raise_error(OmniAgent::Error, /rate limited/)

      expect(completions).to have_received(:create).exactly(3).times
    ensure
      OmniAgent.configuration.max_retries = 3
    end

    it "does not retry on non-retryable errors" do
      messages = [ { role: "user", content: "Hello" } ]
      completions = double("completions")
      chat = double("chat", completions: completions)
      client_instance = instance_double(OpenAI::Client, chat: chat)
      allow(OpenAI::Client).to receive(:new).and_return(client_instance)

      bad_request_error = OpenAI::Errors::BadRequestError.new(
        url: URI("https://api.openai.com"), status: 400, headers: {}, body: nil, request: nil, response: nil, message: "bad request"
      )
      allow(completions).to receive(:create).and_raise(bad_request_error)

      expect {
        described_class.new(api_key: "token", model: "gpt-test").chat(messages: messages)
      }.to raise_error(OmniAgent::Error, /bad request/)

      expect(completions).to have_received(:create).once
    end
  end

  describe "integration tests" do
    before do
      stub_const("OpenAISpecAgent", Module.new)
      stub_const("OpenAISpecAgent::Tools", Module.new)

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

      stub_const("OpenAISpecAgent::Tools::WebSearch", web_search_class)
    end

    it "formats tools correctly in the payload" do
      provider = described_class.new(api_key: "token", model: "gpt-test")

      completions = double("completions")
      chat = double("chat", completions: completions)
      expect(provider).to receive(:client).and_return(double(chat: chat))
      expect(provider).to receive(:format_tool).with(OpenAISpecAgent::Tools::WebSearch).and_call_original
      expect(completions).to receive(:create).with(
        model: "gpt-test",
        messages: [ { role: "user", content: "Search the web" } ],
        tools: [
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
                required: [ "query" ],
                additionalProperties: false
              }
            }
          }
        ]
      ).and_return({})

      provider.chat(messages: [ { role: "user", content: "Search the web" } ], tools: [ OpenAISpecAgent::Tools::WebSearch ])
    end
  end
end
