require_relative "../../spec_helper"
require_relative "../../../lib/omni_agent"
require "active_support/core_ext/string/inflections"
require "stringio"
require "tmpdir"

RSpec.describe OmniAgent::StockAgents::OCR do
  let(:png) { "\x89PNG\r\n\x1A\nrest".b }
  let(:pdf) { "%PDF-1.7 rest".b }
  let(:agent) { Class.new(described_class) { provider :mock }.new }

  def user_content(response)
    response.raw_request[:messages].find { |message| message[:role] == "user" }[:content]
  end

  def data_url(type, bytes)
    "data:#{type};base64,#{[ bytes ].pack('m0')}"
  end

  it "is registered as a stock agent" do
    expect(OmniAgent::StockAgents.find(:ocr)).to eq(described_class)
  end

  it "returns structured output validated against its output schema" do
    response = agent.run("input")

    expect(response.structured_output).to be_a(Hash)
  end

  it "sends plain strings unchanged" do
    expect(user_content(agent.run("just text"))).to eq("just text")
  end

  it "turns a single image into an image part" do
    expect(user_content(agent.run(StringIO.new(png)))).to eq([
      { type: "image_url", image_url: { url: data_url("image/png", png) } }
    ])
  end

  it "turns several sources into ordered content parts" do
    Dir.mktmpdir do |dir|
      path = Pathname(dir).join("scan.pdf")
      path.binwrite(pdf)
      attachment = Struct.new(:download).new("\xFF\xD8\xFFjpeg".b)

      content = user_content(agent.run([ "Totals only", path, attachment, URI("https://example.com/a.webp") ]))

      expect(content).to eq([
        { type: "text", text: "Totals only" },
        { type: "file", file: { filename: "document.pdf", file_data: data_url("application/pdf", pdf) } },
        { type: "image_url", image_url: { url: data_url("image/jpeg", "\xFF\xD8\xFFjpeg".b) } },
        { type: "image_url", image_url: { url: "https://example.com/a.webp" } }
      ])
    end
  end

  it "detects WEBP images" do
    webp = "RIFF\x00\x00\x00\x00WEBPVP8 ".b

    expect(user_content(agent.run([ StringIO.new(webp) ])).first.dig(:image_url, :url)).to start_with("data:image/webp;base64,")
  end

  it "rejects files that aren't images or PDFs" do
    expect { agent.run([ StringIO.new("plain text file") ]) }.to raise_error(OmniAgent::Error, /PNG, JPEG, GIF, WEBP and PDF/)
  end

  it "rejects sources it can't read" do
    expect { agent.run([ 42 ]) }.to raise_error(ArgumentError, /can't read a Integer/)
  end
end
