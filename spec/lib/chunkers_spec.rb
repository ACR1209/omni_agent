require_relative "../spec_helper"
require "active_support"
require "active_support/core_ext/object/blank"
require_relative "../../lib/omni_agent"

RSpec.describe OmniAgent::Chunkers do
  let(:paragraphs) { (1..6).map { |n| "Paragraph #{n} has a few words in it." }.join("\n\n") }

  describe OmniAgent::Chunkers::Recursive do
    it "keeps short text as one chunk" do
      expect(described_class.call("Refunds take 30 days.", size: 100, overlap: 0)).to eq([ "Refunds take 30 days." ])
    end

    it "splits on paragraphs before anything finer, keeping chunks under size" do
      chunks = described_class.call(paragraphs, size: 80, overlap: 0)

      expect(chunks).to eq([
        "Paragraph 1 has a few words in it.\n\nParagraph 2 has a few words in it.",
        "Paragraph 3 has a few words in it.\n\nParagraph 4 has a few words in it.",
        "Paragraph 5 has a few words in it.\n\nParagraph 6 has a few words in it."
      ])
    end

    it "repeats whole trailing pieces from the previous chunk as overlap" do
      chunks = described_class.call(paragraphs, size: 80, overlap: 40)

      expect(chunks[1]).to start_with("Paragraph 2")
      expect(chunks).to all(satisfy { |chunk| chunk.length <= 80 })
    end

    it "falls back to sentences, then words, then a hard cut" do
      long_sentences = "One two three. Four five six. Seven eight nine."
      expect(described_class.call(long_sentences, size: 20, overlap: 0)).to eq([ "One two three.", "Four five six.", "Seven eight nine." ])
      expect(described_class.call("a" * 25, size: 10, overlap: 0)).to eq([ "a" * 10, "a" * 10, "a" * 5 ])
    end
  end

  describe OmniAgent::Chunkers::Markdown do
    let(:text) do
      <<~MD
        Intro text.

        # Billing

        How billing works.

        ## Refunds

        Refunds take 30 days.

        ```sh
        # not a heading
        ```

        # Shipping

        We ship worldwide.
      MD
    end

    it "skips headings with nothing under them" do
      expect(described_class.call("# Billing\n\n## Refunds\n\n30 days.", size: 1000, overlap: 0))
        .to eq([ { content: "## Refunds\n\n30 days.", metadata: { "headings" => [ "Billing", "Refunds" ] } } ])
    end

    it "makes one chunk per section, tagged with its heading path" do
      chunks = described_class.call(text, size: 1000, overlap: 0)

      expect(chunks.map { |chunk| chunk[:metadata] }).to eq([
        {}, { "headings" => [ "Billing" ] }, { "headings" => [ "Billing", "Refunds" ] }, { "headings" => [ "Shipping" ] }
      ])
      expect(chunks[2][:content]).to start_with("## Refunds").and include("# not a heading")
    end

    it "splits sections longer than size" do
      chunks = described_class.call("# Big\n\n#{paragraphs}", size: 80, overlap: 0)

      expect(chunks.length).to be > 1
      expect(chunks.map { |chunk| chunk[:metadata] }.uniq).to eq([ { "headings" => [ "Big" ] } ])
    end
  end

  describe OmniAgent::Chunkers::Hierarchical do
    it "gives every child chunk its parent section as context" do
      chunks = described_class.call("# Refunds\n\n#{paragraphs}", size: 80, overlap: 0)

      expect(chunks.length).to be > 1
      expect(chunks.map { |chunk| chunk[:context] }.uniq.length).to eq(1)
      expect(chunks.first[:context]).to include("Paragraph 1", "Paragraph 6")
      expect(chunks).to all(include(metadata: { "headings" => [ "Refunds" ] }))
    end
  end

  describe ".chunk" do
    it "accepts any callable and normalizes Strings and Hashes, dropping blanks" do
      chunker = ->(text, **) { [ text.upcase, " ", { "content" => "b", "context" => "parent" } ] }

      expect(described_class.chunk("a", chunker: chunker, size: 10, overlap: 0)).to eq([
        { content: "A", context: nil, metadata: {} },
        { content: "b", context: "parent", metadata: {} }
      ])
    end

    it "rejects unknown chunker names" do
      expect { described_class.chunk("a", chunker: :semantic, size: 10, overlap: 0) }
        .to raise_error(ArgumentError, /Unknown chunker :semantic. Use recursive, markdown, hierarchical/)
    end
  end
end
