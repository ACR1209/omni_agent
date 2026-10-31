require_relative "../../rails_helper"
require "rails/generators"
require "generators/omni_agent/stock_agent/stock_agent_generator"

RSpec.describe OmniAgent::Generators::StockAgentGenerator do
  around do |example|
    Dir.mktmpdir do |dir|
      @destination = dir
      example.run
    end
  end

  def generate(name, *args)
    capture = StringIO.new
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = capture
    $stderr = capture
    described_class.start([ name, *args ], destination_root: @destination)
    capture.string
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end

  def agent_source(file_name)
    File.read(File.join(@destination, "app", "agents", "#{file_name}.rb"))
  end

  it "writes an output block for the declared fields" do
    generate("InvoiceOcr", "--from=ocr", "--fields", "invoice_number:string", "total:number")

    expect(agent_source("invoice_ocr")).to eq(<<~RUBY)
      class InvoiceOcr < OmniAgent::StockAgents::OCR
        output do
          string :invoice_number
          number :total
        end
      end
    RUBY
    expect(File).to exist(File.join(@destination, "app", "agents", "invoice_ocr", "prompt.md.erb"))
  end

  it "writes a labels call for stock agents with labels" do
    generate("TicketTriage", "--from=classifier", "--labels", "billing", "bug", "off-topic")

    expect(agent_source("ticket_triage")).to eq(<<~RUBY)
      class TicketTriage < OmniAgent::StockAgents::Classifier
        labels :billing, :bug, :off_topic
      end
    RUBY
  end

  it "adds multiple: true with --multiple" do
    generate("ContentFlags", "--from=classifier", "--labels", "spam", "toxic", "--multiple")

    expect(agent_source("content_flags")).to include("labels :spam, :toxic, multiple: true")
  end

  it "writes a placeholder label without --labels" do
    generate("TicketTriage", "--from=classifier")

    expect(agent_source("ticket_triage")).to include('labels example: "Describe when the agent should pick this label"')
  end

  it "keeps --fields for a custom classifier output" do
    generate("TicketTriage", "--from=classifier", "--fields", "label:string", "urgent:boolean")

    expect(agent_source("ticket_triage")).to include("output do", "boolean :urgent")
  end

  it "rejects --labels together with --fields" do
    output = generate("TicketTriage", "--from=classifier", "--labels", "bug", "--fields", "urgent:boolean")

    expect(output).to include("Pass either --labels or --fields, not both")
    expect(File).not_to exist(File.join(@destination, "app", "agents", "ticket_triage.rb"))
  end

  it "rejects --labels and --multiple for stock agents without labels" do
    expect(generate("InvoiceOcr", "--from=ocr", "--labels", "bug")).to include("only work with stock agents that declare labels")
    expect(generate("InvoiceOcr", "--from=ocr", "--multiple")).to include("only work with stock agents that declare labels")
    expect(File).not_to exist(File.join(@destination, "app", "agents", "invoice_ocr.rb"))
  end
end
