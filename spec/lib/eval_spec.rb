require_relative "../spec_helper"
require_relative "../../lib/omni_agent"
require "fileutils"
require "tmpdir"

class EvalSpecEchoProvider < OmniAgent::Providers::Base
  def chat(messages:, tools: [], **_options)
    content = messages.map { |message| message[:content] }.compact.join("|")
    OmniAgent::Providers::Response.new(content: content, raw_response: {}, tool_calls: [])
  end

  protected

  def default_api_key; nil; end
  def default_model; "echo-spec"; end
end

class EvalSpecAliasAgent < OmniAgent::Agent
  run_aliases :summarize

  def initialize(*)
    super
    @provider = EvalSpecEchoProvider.new
  end

  def available_tools
    []
  end

  private

  def system_prompt(context:, prompt_method: nil)
    prompt_method ? "ALIAS:#{prompt_method}" : "DEFAULT"
  end
end

class EvalSpecContextAgent < OmniAgent::Agent
  def initialize(*)
    super
    @provider = EvalSpecEchoProvider.new
  end

  def available_tools
    []
  end

  private

  def system_prompt(context:, prompt_method: nil)
    "favorite_color:#{@favorite_color}"
  end
end

class EvalSpecCountingProvider < OmniAgent::Providers::Base
  CALL_COUNTS = Hash.new(0)

  def chat(messages:, tools: [], **_options)
    CALL_COUNTS[:count] += 1
    OmniAgent::Providers::Response.new(content: "Lorem ipsum", raw_response: {}, tool_calls: [])
  end

  protected

  def default_api_key; nil; end
  def default_model; "counting-spec"; end
end

class EvalSpecCountingAgent < OmniAgent::Agent
  def initialize(*)
    super
    @provider = EvalSpecCountingProvider.new
  end

  def available_tools
    []
  end
end

class EvalSpecToolCallProvider < OmniAgent::Providers::Base
  def initialize(model: nil)
    super(model: model)
    @calls = 0
  end

  def chat(messages:, tools: [], **_options)
    @calls += 1

    if @calls == 1
      OmniAgent::Providers::Response.new(
        content: nil,
        raw_response: {},
        tool_calls: [ { id: "call_1", name: "GetWeather", arguments: { city: "Paris" } } ]
      )
    else
      OmniAgent::Providers::Response.new(content: "It is sunny in Paris", raw_response: {}, tool_calls: [])
    end
  end

  protected

  def default_api_key; nil; end
  def default_model; "eval-spec-tool-call"; end
end

class EvalSpecToolCallAgent < OmniAgent::Agent
  module Tools
    class GetWeather < OmniAgent::Tool
      input do
        string :city, description: "City to check"
      end

      def execute(city:)
        "Sunny in #{city}"
      end
    end
  end

  def initialize(*)
    super
    @provider = EvalSpecToolCallProvider.new
  end

  def available_tools
    [ Tools::GetWeather ]
  end
end

class EvalSpecMockAgent < OmniAgent::Agent
  provider :mock

  def available_tools
    []
  end
end

RSpec.describe OmniAgent::Eval do
  around do |example|
    previous_config = OmniAgent.instance_variable_get(:@configuration)
    OmniAgent.instance_variable_set(:@configuration, nil)
    OmniAgent.configuration.eval_cache_enabled = false
    example.run
    OmniAgent.instance_variable_set(:@configuration, previous_config)
  end

  describe "class macros" do
    it "stores the configured agent class" do
      eval_class = Class.new(OmniAgent::Eval) { agent EvalSpecMockAgent }

      expect(eval_class.configured_agent).to eq(EvalSpecMockAgent)
    end

    it "accumulates eval_case blocks in order" do
      eval_class = Class.new(OmniAgent::Eval) do
        agent EvalSpecMockAgent

        eval_case("first") { input "hi" }
        eval_case("second") { input "bye" }
      end

      expect(eval_class.configured_cases.map(&:name)).to eq([ "first", "second" ])
    end

    it "raises when run_all is called without a configured agent" do
      eval_class = Class.new(OmniAgent::Eval)

      expect { eval_class.run_all }.to raise_error(OmniAgent::Error, /must declare `agent/)
    end
  end

  describe ".run_all" do
    it "passes a case whose output assertion matches" do
      eval_class = Class.new(OmniAgent::Eval) do
        agent EvalSpecMockAgent

        eval_case "mentions lorem" do
          input "Say something"
          expect_output to_include: "Lorem"
        end
      end

      report = eval_class.run_all

      expect(report).to be_passed
      expect(report.case_results.first.case_name).to eq("mentions lorem")
    end

    it "fails a case whose output assertion does not match" do
      eval_class = Class.new(OmniAgent::Eval) do
        agent EvalSpecMockAgent

        eval_case "mentions something absent" do
          input "Say something"
          expect_output to_include: "this text never appears"
        end
      end

      report = eval_class.run_all

      expect(report).not_to be_passed
      expect(report.case_results.first.outcomes.first).not_to be_passed
    end

    it "asserts on tool calls made during the agent run" do
      eval_class = Class.new(OmniAgent::Eval) do
        agent EvalSpecToolCallAgent

        eval_case "looks up the weather" do
          input "What's the weather in Paris?"
          expect_tool_call :GetWeather, with: { city: "Paris" }
          expect_output to_include: "sunny"
        end
      end

      report = eval_class.run_all

      expect(report).to be_passed
    end

    it "raises EvalAssertionError from raise_on_failure! when a case fails" do
      eval_class = Class.new(OmniAgent::Eval) do
        agent EvalSpecMockAgent

        eval_case "always fails" do
          input "Say something"
          expect_output to_include: "this text never appears"
        end
      end

      report = eval_class.run_all

      expect { report.raise_on_failure! }.to raise_error(OmniAgent::EvalAssertionError, /always fails/)
    end
  end

  describe "input with:" do
    it "forwards the context hash to the agent run" do
      eval_class = Class.new(OmniAgent::Eval) do
        agent EvalSpecContextAgent

        eval_case "passes context through" do
          input "hello", with: { favorite_color: "blue" }
          expect_output to_include: "favorite_color:blue"
        end
      end

      report = eval_class.run_all

      expect(report).to be_passed
    end
  end

  describe "run_alias" do
    it "dispatches to the named run alias instead of #run" do
      eval_class = Class.new(OmniAgent::Eval) do
        agent EvalSpecAliasAgent

        eval_case "uses the summarize alias" do
          run_alias :summarize
          input "long article text"
          expect_output to_include: "ALIAS:summarize"
        end

        eval_case "uses the default run when no alias is set" do
          input "long article text"
          expect_output to_include: "DEFAULT"
        end
      end

      report = eval_class.run_all

      expect(report).to be_passed
    end
  end

  describe "caching" do
    it "does not call the provider twice for the same agent/input/context" do
      previous_cache_path = OmniAgent.configuration.eval_cache_path
      tmp_dir = Dir.mktmpdir
      OmniAgent.configuration.eval_cache_enabled = true
      OmniAgent.configuration.eval_cache_path = File.join(tmp_dir, "eval_cache.json")
      EvalSpecCountingProvider::CALL_COUNTS.clear

      eval_class = Class.new(OmniAgent::Eval) do
        agent EvalSpecCountingAgent

        eval_case("first") { input "Say something" }
        eval_case("second") { input "Say something" }
      end

      eval_class.run_all

      expect(EvalSpecCountingProvider::CALL_COUNTS[:count]).to eq(1)
    ensure
      FileUtils.remove_entry(tmp_dir) if tmp_dir
      OmniAgent.configuration.eval_cache_path = previous_cache_path
    end

    it "calls the provider again after Cache.clear!" do
      previous_cache_path = OmniAgent.configuration.eval_cache_path
      tmp_dir = Dir.mktmpdir
      OmniAgent.configuration.eval_cache_enabled = true
      OmniAgent.configuration.eval_cache_path = File.join(tmp_dir, "eval_cache.json")
      EvalSpecCountingProvider::CALL_COUNTS.clear

      eval_class = Class.new(OmniAgent::Eval) do
        agent EvalSpecCountingAgent

        eval_case("only") { input "Say something" }
      end

      eval_class.run_all
      OmniAgent::Eval::Cache.clear!
      eval_class.run_all

      expect(EvalSpecCountingProvider::CALL_COUNTS[:count]).to eq(2)
    ensure
      FileUtils.remove_entry(tmp_dir) if tmp_dir
      OmniAgent.configuration.eval_cache_path = previous_cache_path
    end
  end

  describe ".golden_set" do
    it "generates one case per row in the dataset file" do
      eval_class = Class.new(OmniAgent::Eval) do
        agent EvalSpecMockAgent

        golden_set File.expand_path("../fixtures/golden/sample.yml", __dir__) do |row|
          expect_output to_include: row[:expected_output]
        end
      end

      expect(eval_class.configured_cases.map(&:name)).to eq([ "lorem case", "ipsum case" ])

      report = eval_class.run_all
      expect(report).to be_passed
    end
  end
end
