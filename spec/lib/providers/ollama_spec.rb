require_relative "../../spec_helper"
require "active_support"
require_relative "../../../lib/omni_agent"
require_relative "../../../lib/omni_agent/providers/base"
require_relative "../../../lib/omni_agent/providers/response"
require_relative "../../../lib/omni_agent/providers/openai"
require_relative "../../../lib/omni_agent/providers/ollama"

RSpec.describe OmniAgent::Providers::Ollama do
  around do |example|
    original_host = ENV["OLLAMA_HOST"]
    original_key = ENV["OLLAMA_API_KEY"]
    original_model = ENV["OLLAMA_MODEL"]
    ENV.delete("OLLAMA_HOST")
    ENV.delete("OLLAMA_API_KEY")
    ENV.delete("OLLAMA_MODEL")
    example.run
    ENV["OLLAMA_HOST"] = original_host
    ENV["OLLAMA_API_KEY"] = original_key
    ENV["OLLAMA_MODEL"] = original_model
  end

  it "defaults to llama3.1 and a placeholder api key" do
    provider = described_class.new

    expect(provider.model).to eq("llama3.1")
  end

  it "honors OLLAMA_MODEL and OLLAMA_API_KEY env overrides" do
    ENV["OLLAMA_MODEL"] = "qwen2.5"
    ENV["OLLAMA_API_KEY"] = "secret"

    provider = described_class.new

    expect(provider.model).to eq("qwen2.5")
    expect(provider.send(:default_api_key)).to eq("secret")
  end

  it "points the client at the local Ollama OpenAI-compat endpoint by default" do
    messages = [ { role: "user", content: "Hello" } ]
    raw_response = { "choices" => [ { "message" => { "content" => "Hi there" } } ] }

    completions = double("completions")
    chat = double("chat", completions: completions)
    client_instance = instance_double(OpenAI::Client, chat: chat)
    expect(OpenAI::Client).to receive(:new)
      .with(api_key: "ollama", base_url: "http://localhost:11434/v1")
      .and_return(client_instance)
    expect(completions).to receive(:create)
      .with(model: "llama3.1", messages: messages)
      .and_return(raw_response)

    result = described_class.new.chat(messages: messages)

    expect(result.content).to eq("Hi there")
  end

  it "honors OLLAMA_HOST when building the client base_url" do
    ENV["OLLAMA_HOST"] = "http://remote-ollama:11434"
    messages = [ { role: "user", content: "Hello" } ]

    completions = double("completions")
    chat = double("chat", completions: completions)
    client_instance = instance_double(OpenAI::Client, chat: chat)
    expect(OpenAI::Client).to receive(:new)
      .with(api_key: "ollama", base_url: "http://remote-ollama:11434/v1")
      .and_return(client_instance)
    allow(completions).to receive(:create)
      .and_return({ "choices" => [ { "message" => { "content" => "Hi" } } ] })

    described_class.new.chat(messages: messages)
  end

  it "streams text delta events and returns the final parsed response" do
    messages = [ { role: "user", content: "Hello" } ]

    delta_events = [
      OpenAI::Helpers::Streaming::ChatContentDeltaEvent.new(delta: "Hi", snapshot: "Hi"),
      OpenAI::Helpers::Streaming::ChatContentDeltaEvent.new(delta: " there", snapshot: "Hi there")
    ]
    final_completion = { "choices" => [ { "message" => { "content" => "Hi there" } } ] }

    chat_stream = instance_double(OpenAI::Helpers::Streaming::ChatCompletionStream)
    allow(chat_stream).to receive(:each) { |&block| delta_events.each(&block) }
    allow(chat_stream).to receive(:get_final_completion).and_return(final_completion)

    completions = double("completions")
    chat = double("chat", completions: completions)
    client_instance = instance_double(OpenAI::Client, chat: chat)
    allow(OpenAI::Client).to receive(:new).and_return(client_instance)
    expect(completions).to receive(:stream)
      .with(model: "llama3.1", messages: messages)
      .and_return(chat_stream)

    events = []
    result = described_class.new.chat(messages: messages, stream: ->(event) { events << event })

    expect(events.map(&:text)).to eq([ "Hi", " there" ])
    expect(result.content).to eq("Hi there")
  end

  it "labels errors as Ollama, not OpenAI" do
    messages = [ { role: "user", content: "Hello" } ]
    completions = double("completions")
    chat = double("chat", completions: completions)
    client_instance = instance_double(OpenAI::Client, chat: chat)
    allow(OpenAI::Client).to receive(:new).and_return(client_instance)
    allow(completions).to receive(:create).and_raise(StandardError.new("connection refused"))

    expect {
      described_class.new.chat(messages: messages)
    }.to raise_error(OmniAgent::Error, /Error during Ollama chat: connection refused/)
  end
end
