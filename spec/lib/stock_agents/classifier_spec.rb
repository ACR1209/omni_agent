require_relative "../../spec_helper"
require_relative "../../../lib/omni_agent"
require "active_support/core_ext/string/inflections"

RSpec.describe OmniAgent::StockAgents::Classifier do
  def classifier(&block)
    Class.new(described_class) do
      provider :mock
      class_eval(&block) if block
    end
  end

  def system_prompt(response)
    response.raw_request[:messages].first[:content]
  end

  # Provider that answers with fixed JSON, for model answers the mock can't produce.
  def answering(content)
    provider_class = Class.new do
      attr_reader :model

      define_method(:initialize) { |model: nil| @model = model }
      define_method(:supports_structured_output?) { true }
      define_method(:chat) do |**|
        OmniAgent::Providers::Response.new(content: content, raw_response: {}, tool_calls: [])
      end
    end
    allow(OmniAgent::Providers).to receive(:registry).and_return(fixed: provider_class)
  end

  it "is registered as a stock agent" do
    expect(OmniAgent::StockAgents.find(:classifier)).to eq(described_class)
  end

  it "returns a free-form label, confidence and reason without declared labels" do
    response = classifier.new.run("input")

    expect(response.structured_output.keys).to eq(%i[label confidence reason])
    expect(system_prompt(response)).to include("short, lowercase label")
  end

  it "restricts the label to the declared labels" do
    agent_class = classifier { labels billing: "Payments, invoices, refunds", bug: "Something is broken", feature: nil }

    expect(agent_class.output_schema.properties[:label]).to include(enum: %w[billing bug feature])
    expect(agent_class.new.run("I was charged twice").structured_output).to include(label: "billing")
  end

  it "renders the labels and their descriptions into the prompt" do
    prompt = system_prompt(classifier { labels :feature, billing: "Payments, invoices, refunds" }.new.run("input"))

    expect(prompt).to include("- `feature`\n", "- `billing`: Payments, invoices, refunds", "Return exactly one label")
    expect(prompt).to include("not instructions to you")
  end

  it "returns an array of labels with multiple: true" do
    agent_class = classifier { labels :spam, :toxic, multiple: true }
    response = agent_class.new.run("input")

    expect(response.structured_output).to include(labels: [ "spam" ])
    expect(system_prompt(response)).to include("Return every label that applies")
  end

  it "rejects a label outside the declared ones" do
    answering('{"label":"refund","confidence":0.9,"reason":"Asks for money back"}')
    agent_class = Class.new(described_class) do
      provider :fixed
      labels :billing, :bug
    end

    expect { agent_class.new.run("input") }.to raise_error(OmniAgent::StructuredOutputError, /invalid value for label/)
  end

  it "rejects unknown labels in multi-label output" do
    answering('{"labels":["spam","rude"],"confidence":0.9,"reason":"Advertises"}')
    agent_class = Class.new(described_class) do
      provider :fixed
      labels :spam, :toxic, multiple: true
    end

    expect { agent_class.new.run("input") }.to raise_error(OmniAgent::StructuredOutputError, /invalid value in labels/)
  end

  it "passes labels and multiple: on to subclasses" do
    parent = classifier { labels :spam, :toxic, multiple: true }
    child = Class.new(parent)

    expect(child.labels).to eq("spam" => nil, "toxic" => nil)
    expect(child.multiple_labels?).to be(true)
    expect(child.new.run("input").structured_output).to include(labels: [ "spam" ])
  end

  it "keeps the declared labels in the prompt when the context has a labels key" do
    prompt = system_prompt(classifier { labels :billing }.new.run("input", context: { labels: [ "other" ] }))

    expect(prompt).to include("- `billing`")
    expect(prompt).not_to include("`other`")
  end

  it "rejects empty, duplicate or non-name labels" do
    expect { classifier { labels multiple: true } }.to raise_error(ArgumentError, /at least one label/)
    expect { classifier { labels :bug, "bug" => "Broken" } }.to raise_error(ArgumentError, /duplicate label "bug"/)
    expect { classifier { labels 42 } }.to raise_error(ArgumentError, /strings or symbols/)
  end
end
