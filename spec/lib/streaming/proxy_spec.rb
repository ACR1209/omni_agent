require_relative "../../spec_helper"
require_relative "../../../lib/omni_agent/streaming/proxy"

RSpec.describe OmniAgent::Streaming::Proxy do
  let(:agent) { double("agent") }
  let(:proxy) { described_class.new(agent) }

  it "forwards method calls and blocks to the wrapped agent" do
    block = -> { }
    expect(agent).to receive(:run).with("Hello", context: { a: 1 }) do |*_args, **_kwargs, &received_block|
      expect(received_block).to eq(block)
      "result"
    end

    result = proxy.run("Hello", context: { a: 1 }, &block)

    expect(result).to eq("result")
  end

  it "delegates respond_to? checks to the wrapped agent" do
    allow(agent).to receive(:respond_to?).with(:ask, false).and_return(true)

    expect(proxy.respond_to?(:ask)).to be(true)
  end
end
