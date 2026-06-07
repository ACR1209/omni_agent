require_relative "../../spec_helper"
require_relative "../../../lib/errors"
require_relative "../../../lib/providers/base"
require_relative "../../../lib/providers/response"
require_relative "../../../lib/providers/openai"

RSpec.describe OmniAgents::Providers::OpenAI do
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

    expect(result).to be_a(OmniAgents::Providers::Response)
    expect(result.content).to eq("Hi there")
    expect(result.raw_response).to eq(raw_response)
  end

  it "uses gpt-4o as the default model" do
    provider = described_class.new(api_key: "token")

    expect(provider.model).to eq("gpt-4o")
  end
end
