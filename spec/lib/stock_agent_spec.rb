require_relative "../spec_helper"
require_relative "../../lib/omni_agent"
require "active_support/core_ext/string/inflections"
require "fileutils"
require "pathname"
require "tmpdir"

RSpec.describe OmniAgent::StockAgent do
  around do |example|
    previous_config = OmniAgent.instance_variable_get(:@configuration)
    OmniAgent.instance_variable_set(:@configuration, nil)

    Dir.mktmpdir do |dir|
      @tmp_dir = dir
      example.run
    end

    OmniAgent.instance_variable_set(:@configuration, previous_config)
  end

  let(:stock_prompts_dir) { File.join(@tmp_dir, "stock", "invoice_reader") }
  let(:app_root) { File.join(@tmp_dir, "app_root") }

  let(:captured) { {} }

  let(:capturing_provider_class) do
    captured_state = captured

    Class.new do
      attr_reader :model

      define_method(:initialize) { |model: nil| @model = model }

      define_method(:chat) do |messages:, tools: [], stream: nil, **options|
        captured_state[:system_prompt] = messages.first[:content]
        captured_state[:options] = options
        OmniAgent::Providers::Response.new(content: '{"result":"ok"}', raw_response: {}, tool_calls: [])
      end
    end
  end

  before do
    allow(OmniAgent::Providers).to receive(:registry).and_return(capturing: capturing_provider_class)

    FileUtils.mkdir_p(stock_prompts_dir)
    File.write(File.join(stock_prompts_dir, "prompt.md.erb"), "Stock prompt for <%= @user %>")

    rails_class = Class.new
    root = Pathname.new(app_root)
    rails_class.define_singleton_method(:root) { root }
    stub_const("Rails", rails_class)

    prompts_dir = stock_prompts_dir
    stub_const("OmniAgent::StockAgents::InvoiceReader", Class.new(described_class) do
      description "Reads invoices"
      provider :capturing, model: "stock-model"
      prompts_path prompts_dir
      run_aliases :summarize

      output do
        string :result
      end
    end)
  end

  describe ".stock_name" do
    it "derives the stock name from the class name" do
      expect(OmniAgent::StockAgents::InvoiceReader.stock_name).to eq(:invoice_reader)
    end

    it "is inherited by host app subclasses" do
      stub_const("MyInvoiceAgent", Class.new(OmniAgent::StockAgents::InvoiceReader))

      expect(MyInvoiceAgent.stock_name).to eq(:invoice_reader)
      expect(MyInvoiceAgent.description).to eq("Reads invoices")
    end
  end

  describe ".prompts_path" do
    it "defaults to the gem's stock_agents directory" do
      stub_const("OmniAgent::StockAgents::Classifier", Class.new(described_class))

      expect(OmniAgent::StockAgents::Classifier.prompts_path)
        .to eq(File.join(OmniAgent::StockAgents.root, "classifier"))
    end
  end

  describe "OmniAgent::StockAgents" do
    it "lists and finds stock agents by name" do
      expect(OmniAgent::StockAgents.all).to include(OmniAgent::StockAgents::InvoiceReader)
      expect(OmniAgent::StockAgents.find(:invoice_reader)).to eq(OmniAgent::StockAgents::InvoiceReader)
      expect(OmniAgent::StockAgents.find("invoice_reader")).to eq(OmniAgent::StockAgents::InvoiceReader)
    end

    it "raises UnknownStockAgentError for an unknown stock agent" do
      expect { OmniAgent::StockAgents.find(:nope) }
        .to raise_error(OmniAgent::UnknownStockAgentError, /Unknown stock agent :nope. Available stock agents: .*invoice_reader/)
    end
  end

  describe "#run" do
    it "renders the stock prompt shipped with the gem" do
      OmniAgent::StockAgents::InvoiceReader.new.run("Invoice text", context: { user: "Ana" })

      expect(captured[:system_prompt]).to eq("Stock prompt for Ana")
    end

    it "renders the stock method prompt for run aliases" do
      File.write(File.join(stock_prompts_dir, "summarize.md.erb"), "Summarize it")

      OmniAgent::StockAgents::InvoiceReader.new.summarize("Invoice text", context: { user: "Ana" })

      expect(captured[:system_prompt]).to eq("Stock prompt for Ana\n\nSummarize it")
    end

    it "appends the host app's prompt for its subclass after the stock prompt" do
      app_prompt_dir = File.join(app_root, "app", "agents", "my_invoice_agent")
      FileUtils.mkdir_p(app_prompt_dir)
      File.write(File.join(app_prompt_dir, "prompt.md.erb"), "Dates use DD/MM/YYYY.")
      stub_const("MyInvoiceAgent", Class.new(OmniAgent::StockAgents::InvoiceReader))

      MyInvoiceAgent.new.run("Invoice text", context: { user: "Ana" })

      expect(captured[:system_prompt]).to eq("Stock prompt for Ana\n\nDates use DD/MM/YYYY.")
    end

    it "lets host app subclasses replace the output schema while keeping the stock configuration" do
      stub_const("MyInvoiceAgent", Class.new(OmniAgent::StockAgents::InvoiceReader) do
        output do
          string :result
          string :invoice_number, required: false
        end
      end)

      agent = MyInvoiceAgent.new
      response = agent.run("Invoice text")

      expect(agent.provider.model).to eq("stock-model")
      expect(captured[:options][:output_schema].properties.keys).to eq(%i[result invoice_number])
      expect(response.structured_output).to eq(result: "ok")
    end

    it "produces schema-valid structured output with the mock provider" do
      mock_agent_class = Class.new(OmniAgent::StockAgents::InvoiceReader) do
        provider :mock

        output do
          string :invoice_number
          number :total
        end
      end
      allow(OmniAgent::Providers).to receive(:registry).and_return(mock: OmniAgent::Providers::Mock)

      response = mock_agent_class.new.run("Invoice text")

      expect(response.structured_output).to eq(invoice_number: OmniAgent::Providers::Mock::LOREM_IPSUM, total: 0.0)
    end
  end
end
