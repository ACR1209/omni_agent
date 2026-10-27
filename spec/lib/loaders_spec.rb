require_relative "../spec_helper"
require "active_support"
require "active_support/core_ext/object/blank"
require "stringio"
require_relative "../../lib/omni_agent"

RSpec.describe OmniAgent::Loaders do
  let(:pdf) { File.binread(File.expand_path("../fixtures/documents/refunds.pdf", __dir__)) }

  before { OmniAgent.instance_variable_set(:@configuration, nil) }
  after { OmniAgent.instance_variable_set(:@configuration, nil) }

  def load(content, **options)
    described_class.load(StringIO.new(content.b), **options)
  end

  describe "auto-detection" do
    it "reads PDFs by content type, extension or magic bytes" do
      expect(load(pdf, content_type: "application/pdf")).to eq("Refunds take 30 days.")
      expect(load(pdf, filename: "refunds.PDF")).to eq("Refunds take 30 days.")
      expect(load(pdf, content_type: "application/octet-stream")).to eq("Refunds take 30 days.")
    end

    it "reads HTML as its visible text, one paragraph per block" do
      html = "<!DOCTYPE html><html><head><script>alert(1)</script></head><body><h1>Refunds</h1><p>Within <b>30</b> days.</p></body></html>"

      expect(load(html)).to eq("Refunds\n\nWithin 30 days.")
      expect(load(html, filename: "refunds.html")).to eq("Refunds\n\nWithin 30 days.")
    end

    it "reads Markdown and plain text as they are" do
      expect(load("# Refunds\n\nWithin 30 days.", filename: "refunds.md")).to eq("# Refunds\n\nWithin 30 days.")
      expect(load("Within 30 days.", content_type: "text/plain; charset=utf-8")).to eq("Within 30 days.")
    end

    it "reads unknown files as text unless they look binary" do
      expect(load("Within 30 days.", filename: "notes.unknown")).to eq("Within 30 days.")
      expect { load("PK\x03\x04\0\0zip", filename: "refunds.zip") }
        .to raise_error(OmniAgent::UnsupportedDocumentError, /Can't read refunds.zip.*config.document_loaders/)
    end

    it "tries loaders from config.document_loaders first" do
      docx = Module.new do
        def self.handles?(filename:, **)
          filename.end_with?(".docx")
        end

        def self.call(io, **)
          "docx text"
        end
      end
      OmniAgent.configure { |config| config.document_loaders = { docx: docx } }

      expect(load("PK\x03\x04\0", filename: "refunds.docx")).to eq("docx text")
    end
  end

  describe "enforced loaders" do
    it "uses the named loader without detecting" do
      expect(load("<p>Hi</p>", as: :text)).to eq("<p>Hi</p>")
      expect(load(pdf, as: :pdf, filename: "upload.bin")).to eq("Refunds take 30 days.")
    end

    it "accepts any callable" do
      expect(load("hi", as: ->(io, **) { io.read.upcase })).to eq("HI")
    end

    it "rejects unknown loader names" do
      expect { load("hi", as: :docx) }.to raise_error(ArgumentError, /Unknown loader :docx. Use :auto, pdf, html, markdown, text/)
    end
  end

  it "cleans encodings, NUL bytes, CRLFs and blank lines" do
    expect(load("caf\xC3\xA9 \xFF\0ok  \r\n\r\n\r\n\r\nnext", as: :text)).to eq("café ok\n\nnext")
  end
end
