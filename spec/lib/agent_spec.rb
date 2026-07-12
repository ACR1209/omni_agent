require_relative "../spec_helper"
require_relative "../../lib/omni_agent"
require_relative "../../lib/omni_agent/agent"
require_relative "../../lib/omni_agent/errors"
require "active_support/core_ext/string/inflections"
require "fileutils"
require "pathname"
require "tmpdir"

RSpec.describe OmniAgent::Agent do
  around do |example|
    previous_config = OmniAgent.instance_variable_get(:@configuration)
    OmniAgent.instance_variable_set(:@configuration, nil)
    example.run
    OmniAgent.instance_variable_set(:@configuration, previous_config)
  end

  let(:provider_class) do
    Class.new do
      attr_reader :model, :last_chat_options

      def initialize(model: nil)
        @model = model
      end

      def chat(messages:, tools: [], stream: nil, **options)
        @last_chat_options = options
        OmniAgent::Providers::Response.new(content: "ok", raw_response: {}, tool_calls: [])
      end
    end
  end

  before do
    allow(OmniAgent::Providers).to receive(:registry).and_return(test_provider: provider_class)
  end

  it "uses OmniAgent.configuration.default_provider when agent class does not define a provider" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class)
    agent = agent_class.new

    expect(agent.provider).to be_a(provider_class)
    expect(agent.provider.model).to be_nil
  end

  it "allows overriding only the model while using the configured default provider" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class)
    agent = agent_class.new(model_override: "gpt-custom")

    expect(agent.provider).to be_a(provider_class)
    expect(agent.provider.model).to eq("gpt-custom")
  end

  it "allows setting model via use_model without passing model through provider" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class) do
      use_model "gpt-from-use-model"
    end
    agent = agent_class.new

    expect(agent.provider).to be_a(provider_class)
    expect(agent.provider.model).to eq("gpt-from-use-model")
  end

  it "resolves a registered provider by name" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }
    agent_class = Class.new(described_class)
    agent = agent_class.new

    provider = agent.send(:resolve_provider, :test_provider, "gpt-resolved")

    expect(provider).to be_a(provider_class)
    expect(provider.model).to eq("gpt-resolved")
  end

  it "raises OmniAgent::UnknownProviderError for an unregistered provider name" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }
    agent_class = Class.new(described_class)
    agent = agent_class.new

    expect do
      agent.send(:resolve_provider, :nonexistent, "gpt-resolved")
    end.to raise_error(OmniAgent::UnknownProviderError, /Unknown provider :nonexistent.*test_provider/)
  end

  it "raises when provider is declared after use_model" do
    expect do
      Class.new(described_class) do
        use_model "gpt-ordered"
        provider :test_provider
      end
    end.to raise_error(OmniAgent::Error, /Cannot combine `provider` and `use_model`/)
  end

  it "raises when use_model is declared after provider" do
    expect do
      Class.new(described_class) do
        provider :test_provider, model: "gpt-provider"
        use_model "gpt-use-model"
      end
    end.to raise_error(OmniAgent::Error, /Cannot combine `provider` and `use_model`/)
  end

  it "passes DSL options through to provider chat" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class) do
      options temperature: 0.2, top_p: 0.8
    end
    agent = agent_class.new
    allow(agent).to receive(:available_tools).and_return([])
    result = agent.run("Hello")

    expect(result).to be_a(OmniAgent::Providers::Response)
    expect(result.answer).to eq("ok")
    expect(result.raw_response).to eq({})
    expect(agent.provider.last_chat_options).to eq(temperature: 0.2, top_p: 0.8)
  end

  it "merges options_override over DSL options" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class) do
      options temperature: 0.2, top_p: 0.8
    end
    agent = agent_class.new(options_override: { temperature: 0.6 })
    allow(agent).to receive(:available_tools).and_return([])
    agent.run("Hello")

    expect(agent.provider.last_chat_options).to eq(temperature: 0.6, top_p: 0.8)
  end

  it "executes before_generation and after_generation around a run" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class) do
      before_generation :mark_before
      after_generation :mark_after

      attr_reader :events

      def initialize(...)
        super
        @events = []
      end

      def mark_before
        events << :before
      end

      def mark_after
        events << :after
      end
    end

    agent = agent_class.new
    allow(agent).to receive(:available_tools).and_return([])

    result = agent.run("Hello")

    expect(result.answer).to eq("ok")
    expect(agent.events).to eq([ :before, :after ])
  end

  it "passes run payload to generation callbacks" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class) do
      before_generation :capture_before
      after_generation :capture_after

      attr_reader :captured

      def initialize(...)
        super
        @captured = {}
      end

      def capture_before(payload)
        captured[:before_input] = payload[:input]
        captured[:before_context] = payload[:context]
      end

      def capture_after(payload)
        captured[:after_content] = payload[:response].content
      end
    end

    agent = agent_class.new
    allow(agent).to receive(:available_tools).and_return([])

    agent.run("Hello", context: { request_id: "abc" })

    expect(agent.captured).to eq(
      before_input: "Hello",
      before_context: { request_id: "abc" },
      after_content: "ok",
    )
  end

  it "exposes response.generated_messages in after_generation callbacks" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class) do
      after_generation :capture_after_from_ivars

      attr_reader :captured_after

      def capture_after_from_ivars
        @captured_after = {
          response_content: @response&.content,
          generated_messages_count: @response&.generated_messages&.size,
          last_generated_role: @response&.generated_messages&.last&.dig(:role)
        }
      end
    end

    agent = agent_class.new
    allow(agent).to receive(:available_tools).and_return([])

    agent.run("Hello")

    expect(agent.captured_after).to eq(
      response_content: "ok",
      generated_messages_count: 2,
      last_generated_role: "assistant"
    )
  end

  it "exposes payload context as instance variables for zero-arity callbacks" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class) do
      before_generation :capture_from_ivars

      attr_reader :captured_actor

      def capture_from_ivars
        @captured_actor = [ @actor_type, @actor_id ]
      end
    end

    agent = agent_class.new
    allow(agent).to receive(:available_tools).and_return([])

    agent.run("Hello", context: { actor_type: "User", actor_id: 42 })

    expect(agent.captured_actor).to eq([ "User", 42 ])
  end

  it "syncs context updates from instance variables back into payload" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class) do
      before_generation :mutate_context
      after_generation :capture_context_after_sync

      attr_reader :captured_context

      def mutate_context(_payload)
        @actor_id = @actor_id.to_i + 1
        @actor_type = "Person"
      end

      def capture_context_after_sync(payload)
        @captured_context = payload[:context].dup
      end
    end

    agent = agent_class.new
    allow(agent).to receive(:available_tools).and_return([])

    agent.run("Hello", context: { actor_type: "User", actor_id: 41 })

    expect(agent.captured_context).to eq(actor_type: "Person", actor_id: 42)
  end

  it "requires at least one method name for before_generation" do
    expect do
      Class.new(described_class) do
        before_generation
      end
    end.to raise_error(ArgumentError, /before_generation requires at least one method name/)
  end

  it "requires at least one method name for after_generation" do
    expect do
      Class.new(described_class) do
        after_generation
      end
    end.to raise_error(ArgumentError, /after_generation requires at least one method name/)
  end

  it "rejects non-method callback values" do
    expect do
      Class.new(described_class) do
        before_generation Object.new
      end
    end.to raise_error(ArgumentError, /before_generation callbacks must be method names/)
  end

  it "stores normalized tags from the tags DSL" do
    agent_class = Class.new(described_class) do
      tags :math, "person", :math
    end

    expect(agent_class.tags).to eq([ :math, :person ])
  end

  it "returns current tags when called with no arguments" do
    agent_class = Class.new(described_class) do
      tags :math
    end

    expect(agent_class.tags).to eq([ :math ])
  end

  it "rejects non string and non symbol tag values" do
    expect do
      Class.new(described_class) do
        tags :math, 123
      end
    end.to raise_error(ArgumentError, /tags must be strings or symbols/)
  end

  it "keeps tags internal and does not send them to provider chat" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class) do
      tags :math, :person
      options temperature: 0.4
    end

    agent = agent_class.new
    allow(agent).to receive(:available_tools).and_return([])

    agent.run("Hello")

    expect(agent.provider.last_chat_options).to eq(temperature: 0.4)
  end

  it "allows overriding tool_filter to select tools by tool tags" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    math_tool = Class.new(OmniAgent::Tool) do
      tags :math
    end

    people_tool = Class.new(OmniAgent::Tool) do
      tags :person
    end

    agent_class = Class.new(described_class) do
      def tool_filter(tools:, agent_tags:)
        tools.select { |tool_class| tool_class.tags.include?(:math) }
      end
    end

    agent = agent_class.new

    filtered = agent.send(:tool_filter, tools: [ math_tool, people_tool ], agent_tags: agent_class.tags)

    expect(filtered).to eq([ math_tool ])
  end

  it "allows overriding tool_filter to select tools by metadata" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    research_tool = Class.new(OmniAgent::Tool) do
      metadata domain: :research
    end

    utility_tool = Class.new(OmniAgent::Tool) do
      metadata domain: :utility
    end

    agent_class = Class.new(described_class) do
      def tool_filter(tools:, agent_tags:)
        tools.select { |tool_class| tool_class.metadata[:domain] == :research }
      end
    end

    agent = agent_class.new

    filtered = agent.send(:tool_filter, tools: [ research_tool, utility_tool ], agent_tags: agent_class.tags)

    expect(filtered).to eq([ research_tool ])
  end

  it "allows overriding tool_filter to select tools using agent tags" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    math_tool = Class.new(OmniAgent::Tool) do
      tags :math
    end

    people_tool = Class.new(OmniAgent::Tool) do
      tags :person
    end

    agent_class = Class.new(described_class) do
      tags :math

      def tool_filter(tools:, agent_tags:)
        tools.select { |tool_class| (tool_class.tags & agent_tags).any? }
      end
    end

    agent = agent_class.new

    filtered = agent.send(:tool_filter, tools: [ math_tool, people_tool ], agent_tags: agent_class.tags)

    expect(filtered).to eq([ math_tool ])
  end

  it "uses tool_filter result for provider chat tools" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    alpha_tool = Class.new(OmniAgent::Tool)
    beta_tool = Class.new(OmniAgent::Tool)

    agent_class = Class.new(described_class) do
      def tool_filter(tools:, agent_tags:)
        tools.take(1)
      end
    end

    agent = agent_class.new
    captured_tools = nil

    allow(agent).to receive(:available_tools).and_return([ alpha_tool, beta_tool ])
    allow(agent.provider).to receive(:chat) do |messages:, tools: [], **_options|
      captured_tools = tools
      OmniAgent::Providers::Response.new(content: "ok", raw_response: {}, tool_calls: [])
    end

    agent.run("Hello")

    expect(captured_tools).to eq([ alpha_tool ])
  end

  it "stops generation loop after processing all tool calls when any called tool sets stops_generation" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    executed_tools = []

    stub_const("RegularTool", Class.new(OmniAgent::Tool) do
      define_method(:execute) do |**_args|
        executed_tools << :regular
        "regular done"
      end
    end)

    stub_const("StopLoopTool", Class.new(OmniAgent::Tool) do
      stops_generation

      define_method(:execute) do |**_args|
        executed_tools << :stop
        "stop now"
      end
    end)

    agent_class = Class.new(described_class)
    agent = agent_class.new

    response_with_tool_call = OmniAgent::Providers::Response.new(
      content: nil,
      raw_response: {
        "choices" => [
          {
            "message" => {
              "tool_calls" => [
                {
                  "id" => "call_0",
                  "type" => "function",
                  "function" => {
                    "name" => "RegularTool",
                    "arguments" => "{}"
                  }
                },
                {
                  "id" => "call_1",
                  "type" => "function",
                  "function" => {
                    "name" => "StopLoopTool",
                    "arguments" => "{}"
                  }
                }
              ]
            }
          }
        ]
      },
      tool_calls: [
        {
          id: "call_0",
          name: "RegularTool",
          arguments: {}
        },
        {
          id: "call_1",
          name: "StopLoopTool",
          arguments: {}
        }
      ]
    )

    allow(agent).to receive(:available_tools).and_return([ RegularTool, StopLoopTool ])
    expect(agent.provider).to receive(:chat).once.and_return(response_with_tool_call)

    result = agent.run("Hello")

    expect(result).to eq(response_with_tool_call)
    expect(executed_tools).to eq([ :regular, :stop ])
  end

  it "does not send assistant content as nil when continuing after tool calls" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    stub_const("ContinueTool", Class.new(OmniAgent::Tool) do
      def execute(**_args)
        "tool result"
      end
    end)

    agent_class = Class.new(described_class)
    agent = agent_class.new

    response_with_tool_call = OmniAgent::Providers::Response.new(
      content: nil,
      raw_response: {},
      tool_calls: [
        {
          id: "call_1",
          name: "ContinueTool",
          arguments: {}
        }
      ]
    )

    final_response = OmniAgent::Providers::Response.new(content: "done", raw_response: {}, tool_calls: [])
    captured_second_messages = nil

    allow(agent).to receive(:available_tools).and_return([ ContinueTool ])
    expect(agent.provider).to receive(:chat).ordered.and_return(response_with_tool_call)
    expect(agent.provider).to receive(:chat).ordered do |messages:, tools: [], **_options|
      captured_second_messages = messages
      final_response
    end

    result = agent.run("Hello")

    assistant_message = captured_second_messages[2]
    expect(assistant_message[:role]).to eq("assistant")
    expect(assistant_message.key?(:content)).to be(false)
    expect(assistant_message[:tool_calls]).to be_a(Array)
    expect(assistant_message[:tool_calls].first.dig("function", "name")).to eq("ContinueTool")
    expect(result).to eq(final_response)
    expect(result.generated_messages.map { |m| m[:role] }).to eq([ "user", "assistant", "tool", "assistant" ])
    expect(result.generated_messages[1][:tool_calls].first.dig("function", "name")).to eq("ContinueTool")
    expect(result.generated_messages[2]).to eq(role: "tool", tool_call_id: "call_1", name: "ContinueTool", content: "tool result")
  end

  it "raises MaxToolIterationsError instead of looping forever when the model keeps calling tools" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }
    OmniAgent.configuration.max_tool_iterations = 3

    stub_const("LoopingTool", Class.new(OmniAgent::Tool) do
      def execute(**_args)
        "tool result"
      end
    end)

    agent_class = Class.new(described_class)
    agent = agent_class.new

    never_ending_response = OmniAgent::Providers::Response.new(
      content: nil,
      raw_response: {},
      tool_calls: [ { id: "call_x", name: "LoopingTool", arguments: {} } ]
    )

    allow(agent).to receive(:available_tools).and_return([ LoopingTool ])
    allow(agent.provider).to receive(:chat).and_return(never_ending_response)

    expect do
      agent.run("Hello")
    end.to raise_error(OmniAgent::MaxToolIterationsError, /Exceeded max_tool_iterations \(3\)/)

    expect(agent.provider).to have_received(:chat).exactly(3).times
  end

  it "supports class-level with helper to prefill context" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class) do
      before_generation :capture_before

      attr_reader :captured_context

      def capture_before(payload)
        @captured_context = payload[:context]
      end
    end

    agent = agent_class.with(user: "Alice")
    allow(agent).to receive(:available_tools).and_return([])

    agent.run("Hello")

    expect(agent.captured_context).to eq(user: "Alice")
  end

  it "merges with helper context with run context, preferring run context" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class) do
      before_generation :capture_before

      attr_reader :captured_context

      def capture_before(payload)
        @captured_context = payload[:context]
      end
    end

    agent = agent_class.with(user: "Alice", locale: "en")
    allow(agent).to receive(:available_tools).and_return([])

    agent.run("Hello", context: { locale: "es", request_id: "123" })

    expect(agent.captured_context).to eq(user: "Alice", locale: "es", request_id: "123")
  end

  it "includes context history before the current user input" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class)
    agent = agent_class.with(
      history: [
        { role: "user", content: "Earlier question" },
        { role: "assistant", content: "Earlier answer" }
      ]
    )

    captured_messages = nil
    allow(agent).to receive(:available_tools).and_return([])
    allow(agent.provider).to receive(:chat) do |messages:, tools: [], **_options|
      captured_messages = messages
      OmniAgent::Providers::Response.new(content: "ok", raw_response: {}, tool_calls: [])
    end

    agent.run("Hello now")

    expect(captured_messages.map { |m| m[:role] }.first(4)).to eq([ "system", "user", "assistant", "user" ])
    expect(captured_messages[1][:content]).to eq("Earlier question")
    expect(captured_messages[2][:content]).to eq("Earlier answer")
    expect(captured_messages[3][:content]).to eq("Hello now")
  end

  it "allows mutating history via instance variables in callbacks" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class) do
      before_generation :extend_history

      def extend_history
        @history ||= []
        @history << { role: "assistant", content: "Injected from callback" }
      end
    end

    agent = agent_class.with(history: [ { role: "user", content: "Older message" } ])

    captured_messages = nil
    allow(agent).to receive(:available_tools).and_return([])
    allow(agent.provider).to receive(:chat) do |messages:, tools: [], **_options|
      captured_messages = messages
      OmniAgent::Providers::Response.new(content: "ok", raw_response: {}, tool_calls: [])
    end

    agent.run("Hello now")

    expect(captured_messages.map { |m| m[:content] }).to include("Injected from callback")
    expect(captured_messages[-2]).to eq(role: "user", content: "Hello now")
  end

  it "uses base prompt when method prompt file is missing" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    Dir.mktmpdir do |dir|
      app_agents_dir = File.join(dir, "app", "agents", "support_agent")
      FileUtils.mkdir_p(app_agents_dir)
      File.write(File.join(app_agents_dir, "prompt.md.erb"), "Base prompt for <%= @user %>")

      rails_class = Class.new do
        define_singleton_method(:root) { Pathname.new(dir) }
      end

      stub_const("Rails", rails_class)

      support_agent_class = Class.new(described_class) do
        run_aliases :triage
      end
      stub_const("SupportAgent", support_agent_class)

      agent = SupportAgent.new
      captured_system_prompt = nil

      allow(agent).to receive(:available_tools).and_return([])
      allow(agent.provider).to receive(:chat) do |messages:, tools: [], **_options|
        captured_system_prompt = messages.first[:content]
        OmniAgent::Providers::Response.new(content: "ok", raw_response: {}, tool_calls: [])
      end

      agent.triage("Handle ticket", context: { user: "Alice" })

      expect(captured_system_prompt).to eq("Base prompt for Alice")
    end
  end

  it "combines base prompt and method prompt when both files exist" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    Dir.mktmpdir do |dir|
      app_agents_dir = File.join(dir, "app", "agents", "support_agent")
      FileUtils.mkdir_p(app_agents_dir)
      File.write(File.join(app_agents_dir, "prompt.md.erb"), "Base prompt for <%= @user %>")
      File.write(File.join(app_agents_dir, "triage.md.erb"), "Triage instructions for <%= @topic %>")

      rails_class = Class.new do
        define_singleton_method(:root) { Pathname.new(dir) }
      end

      stub_const("Rails", rails_class)

      support_agent_class = Class.new(described_class) do
        run_aliases :triage
      end
      stub_const("SupportAgent", support_agent_class)

      agent = SupportAgent.new
      captured_system_prompt = nil

      allow(agent).to receive(:available_tools).and_return([])
      allow(agent.provider).to receive(:chat) do |messages:, tools: [], **_options|
        captured_system_prompt = messages.first[:content]
        OmniAgent::Providers::Response.new(content: "ok", raw_response: {}, tool_calls: [])
      end

      agent.triage("Handle ticket", context: { user: "Alice", topic: "refund" })

      expect(captured_system_prompt).to eq("Base prompt for Alice\n\nTriage instructions for refund")
    end
  end

  it "allows plain zero-arity methods to act as run entrypoints when called with input" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    Dir.mktmpdir do |dir|
      app_agents_dir = File.join(dir, "app", "agents", "spec_test_agent")
      FileUtils.mkdir_p(app_agents_dir)
      File.write(File.join(app_agents_dir, "prompt.md.erb"), "Base prompt")
      File.write(File.join(app_agents_dir, "test.md.erb"), "Method prompt for <%= @user %>")

      rails_class = Class.new do
        define_singleton_method(:root) { Pathname.new(dir) }
      end

      stub_const("Rails", rails_class)

      spec_test_agent_class = Class.new(described_class) do
        def test
          "no-arg behavior"
        end
      end
      stub_const("SpecTestAgent", spec_test_agent_class)

      agent = SpecTestAgent.new
      captured_system_prompt = nil

      allow(agent).to receive(:available_tools).and_return([])
      allow(agent.provider).to receive(:chat) do |messages:, tools: [], **_options|
        captured_system_prompt = messages.first[:content]
        OmniAgent::Providers::Response.new(content: "ok", raw_response: {}, tool_calls: [])
      end

      response = agent.test("Hello", user: "Alice")

      expect(response.answer).to eq("ok")
      expect(captured_system_prompt).to eq("Base prompt\n\nMethod prompt for Alice")
      expect(agent.test).to eq("no-arg behavior")
    end
  end

  it "renders prompt templates with context values changed through instance variables" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    Dir.mktmpdir do |dir|
      app_agents_dir = File.join(dir, "app", "agents", "support_agent")
      FileUtils.mkdir_p(app_agents_dir)
      File.write(File.join(app_agents_dir, "prompt.md.erb"), "Actor: <%= @actor_type %>#<%= @actor_id %>")

      rails_class = Class.new do
        define_singleton_method(:root) { Pathname.new(dir) }
      end

      stub_const("Rails", rails_class)

      support_agent_class = Class.new(described_class) do
        before_generation :prepare_context

        def prepare_context
          @actor_type = "Person"
          @actor_id = @actor_id.to_i + 1
        end
      end
      stub_const("SupportAgent", support_agent_class)

      agent = SupportAgent.new
      captured_system_prompt = nil

      allow(agent).to receive(:available_tools).and_return([])
      allow(agent.provider).to receive(:chat) do |messages:, tools: [], **_options|
        captured_system_prompt = messages.first[:content]
        OmniAgent::Providers::Response.new(content: "ok", raw_response: {}, tool_calls: [])
      end

      agent.run("Hello", context: { actor_type: "User", actor_id: 41 })

      expect(captured_system_prompt).to eq("Actor: Person#42")
    end
  end

  it "allows alias entrypoint methods to return @message without explicit return" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class) do
      def test
        @message = "message from ivar"
      end
    end

    agent = agent_class.new

    expect(agent.test).to eq("message from ivar")
  end

  it "always runs alias entrypoint logic before generation" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class) do
      attr_reader :before_run_logic_called

      def test
        @before_run_logic_called = true
        @message = "computed input"
      end
    end

    agent = agent_class.new
    allow(agent).to receive(:available_tools).and_return([])

    result = agent.test("Hello")

    expect(result.answer).to eq("ok")
    expect(agent.before_run_logic_called).to eq(true)
  end

  it "supports private callback methods without exposing them as public entrypoints" do
    OmniAgent.configure { |config| config.default_provider = :test_provider }

    agent_class = Class.new(described_class) do
      before_generation :mark_before
      after_generation :mark_after

      attr_reader :events

      def initialize(...)
        super
        @events = []
      end

      private

      def mark_before
        events << :before
      end

      def mark_after
        events << :after
      end
    end

    agent = agent_class.new
    allow(agent).to receive(:available_tools).and_return([])

    result = agent.run("Hello")

    expect(result.answer).to eq("ok")
    expect(agent.events).to eq([ :before, :after ])
    expect(agent.respond_to?(:mark_before)).to be(false)
    expect { agent.mark_before("input") }.to raise_error(NoMethodError)
  end

  describe ".delegate_to" do
    around do |example|
      previous_config = OmniAgent.instance_variable_get(:@configuration)
      OmniAgent.instance_variable_set(:@configuration, nil)
      example.run
      OmniAgent.instance_variable_set(:@configuration, previous_config)
    end

    it "registers a delegated agent as a tool available to the supervisor" do
      OmniAgent.configure { |config| config.default_provider = :test_provider }

      sub_agent_class = Class.new(described_class)
      stub_const("ResearchAgent", sub_agent_class)

      supervisor_class = Class.new(described_class) do
        delegate_to ResearchAgent, as: :research, description: "Look up factual info"
      end
      stub_const("SupervisorAgent", supervisor_class)

      supervisor = SupervisorAgent.new
      tool_class = supervisor.available_tools.first

      expect(supervisor.available_tools.size).to eq(1)
      expect(tool_class.name.split("::").last).to eq("Research")
      expect(tool_class.description).to eq("Look up factual info")
      expect(tool_class < OmniAgent::Tool).to be(true)
    end

    it "raises when delegating to a class that is not an OmniAgent::Agent" do
      not_an_agent = Class.new

      expect do
        Class.new(described_class) do
          delegate_to not_an_agent, as: :research
        end
      end.to raise_error(ArgumentError, /delegate_to requires an OmniAgent::Agent subclass/)
    end

    it "invokes the delegated agent's run and returns its answer when the tool executes" do
      OmniAgent.configure { |config| config.default_provider = :test_provider }

      sub_agent_class = Class.new(described_class)
      stub_const("MathAgent", sub_agent_class)
      allow_any_instance_of(MathAgent).to receive(:available_tools).and_return([])

      supervisor_class = Class.new(described_class) do
        delegate_to MathAgent, as: :calculate, description: "Do arithmetic"
      end
      stub_const("CalcSupervisorAgent", supervisor_class)

      tool_class = CalcSupervisorAgent.new.available_tools.first
      result = tool_class.new.invoke("input" => "2 + 2")

      expect(result).to eq("ok")
    end

    it "invokes the given run_alias on the delegated agent instead of #run" do
      OmniAgent.configure { |config| config.default_provider = :test_provider }

      sub_agent_class = Class.new(described_class) do
        run_aliases :triage
      end
      stub_const("TriageAgent", sub_agent_class)
      allow_any_instance_of(TriageAgent).to receive(:available_tools).and_return([])

      captured_prompt_method = nil
      allow_any_instance_of(TriageAgent).to receive(:run).and_wrap_original do |method, input, **kwargs|
        captured_prompt_method = kwargs[:prompt_method]
        method.call(input, **kwargs)
      end

      supervisor_class = Class.new(described_class) do
        delegate_to TriageAgent, as: :triage_ticket, run_alias: :triage
      end
      stub_const("TriageSupervisorAgent", supervisor_class)

      tool_class = TriageSupervisorAgent.new.available_tools.first
      result = tool_class.new.invoke("input" => "My order is late")

      expect(result).to eq("ok")
      expect(captured_prompt_method).to eq(:triage)
    end

    it "does not forward context to the delegated agent by default" do
      OmniAgent.configure { |config| config.default_provider = :test_provider }

      sub_agent_class = Class.new(described_class)
      stub_const("IsolatedAgent", sub_agent_class)
      allow_any_instance_of(IsolatedAgent).to receive(:available_tools).and_return([])

      captured_context = :not_called
      allow_any_instance_of(IsolatedAgent).to receive(:run).and_wrap_original do |method, input, **kwargs|
        captured_context = kwargs[:context]
        method.call(input, **kwargs)
      end

      supervisor_class = Class.new(described_class) do
        delegate_to IsolatedAgent, as: :isolated
      end
      stub_const("IsolatedSupervisorAgent", supervisor_class)

      tool_class = IsolatedSupervisorAgent.new.available_tools.first
      tool_instance = tool_class.new
      tool_instance.context = { user: "Alice", secret: "shh" }
      tool_instance.invoke("input" => "go")

      expect(captured_context).to eq({})
    end

    it "forwards only the listed context keys when forward: is an array" do
      OmniAgent.configure { |config| config.default_provider = :test_provider }

      sub_agent_class = Class.new(described_class)
      stub_const("PartialForwardAgent", sub_agent_class)
      allow_any_instance_of(PartialForwardAgent).to receive(:available_tools).and_return([])

      captured_context = nil
      allow_any_instance_of(PartialForwardAgent).to receive(:run).and_wrap_original do |method, input, **kwargs|
        captured_context = kwargs[:context]
        method.call(input, **kwargs)
      end

      supervisor_class = Class.new(described_class) do
        delegate_to PartialForwardAgent, as: :partial, forward: [ :user ]
      end
      stub_const("PartialForwardSupervisorAgent", supervisor_class)

      tool_class = PartialForwardSupervisorAgent.new.available_tools.first
      tool_instance = tool_class.new
      tool_instance.context = { user: "Alice", secret: "shh" }
      tool_instance.invoke("input" => "go")

      expect(captured_context).to eq(user: "Alice")
    end

    it "forwards the entire context when forward: true" do
      OmniAgent.configure { |config| config.default_provider = :test_provider }

      sub_agent_class = Class.new(described_class)
      stub_const("FullForwardAgent", sub_agent_class)
      allow_any_instance_of(FullForwardAgent).to receive(:available_tools).and_return([])

      captured_context = nil
      allow_any_instance_of(FullForwardAgent).to receive(:run).and_wrap_original do |method, input, **kwargs|
        captured_context = kwargs[:context]
        method.call(input, **kwargs)
      end

      supervisor_class = Class.new(described_class) do
        delegate_to FullForwardAgent, as: :full, forward: true
      end
      stub_const("FullForwardSupervisorAgent", supervisor_class)

      tool_class = FullForwardSupervisorAgent.new.available_tools.first
      tool_instance = tool_class.new
      tool_instance.context = { user: "Alice", secret: "shh" }
      tool_instance.invoke("input" => "go")

      expect(captured_context).to eq(user: "Alice", secret: "shh")
    end

    it "sets the tool instance's context from the supervisor's run context before invoking" do
      OmniAgent.configure { |config| config.default_provider = :test_provider }

      sub_agent_class = Class.new(described_class)
      stub_const("ContextBridgeAgent", sub_agent_class)
      allow_any_instance_of(ContextBridgeAgent).to receive(:available_tools).and_return([])

      captured_context = nil
      allow_any_instance_of(ContextBridgeAgent).to receive(:run).and_wrap_original do |method, input, **kwargs|
        captured_context = kwargs[:context]
        method.call(input, **kwargs)
      end

      supervisor_class = Class.new(described_class) do
        delegate_to ContextBridgeAgent, as: :bridge, forward: [ :request_id ]
      end
      stub_const("ContextBridgeSupervisorAgent", supervisor_class)

      supervisor = ContextBridgeSupervisorAgent.new
      tool_class = supervisor.available_tools.first

      response_with_tool_call = OmniAgent::Providers::Response.new(
        content: nil,
        raw_response: {},
        tool_calls: [ { id: "call_0", name: tool_class.name.split("::").last, arguments: { "input" => "go" } } ]
      )
      final_response = OmniAgent::Providers::Response.new(content: "done", raw_response: {}, tool_calls: [])

      allow(supervisor.provider).to receive(:chat).and_return(response_with_tool_call, final_response)

      supervisor.run("Hello", context: { request_id: "req-1", other: "dropped" })

      expect(captured_context).to eq(request_id: "req-1")
    end

    it "raises MaxDelegationDepthError once the thread's delegation depth reaches the configured limit" do
      OmniAgent.configure do |config|
        config.default_provider = :test_provider
        config.max_delegation_depth = 2
      end

      sub_agent_class = Class.new(described_class)
      stub_const("DeepAgent", sub_agent_class)

      supervisor_class = Class.new(described_class) do
        delegate_to DeepAgent, as: :go_deep
      end
      stub_const("DeepSupervisorAgent", supervisor_class)

      tool_class = DeepSupervisorAgent.new.available_tools.first

      begin
        Thread.current[:omni_agent_delegation_depth] = 2

        expect do
          tool_class.new.invoke("input" => "go")
        end.to raise_error(OmniAgent::MaxDelegationDepthError, /Exceeded max_delegation_depth \(2\)/)
      ensure
        Thread.current[:omni_agent_delegation_depth] = nil
      end
    end
  end

  describe "streaming" do
    it "does not affect run when no block is given" do
      OmniAgent.configure { |config| config.default_provider = :test_provider }

      agent_class = Class.new(described_class)
      agent = agent_class.new
      allow(agent).to receive(:available_tools).and_return([])

      result = agent.run("Hello")

      expect(result).to be_a(OmniAgent::Providers::Response)
      expect(result.answer).to eq("ok")
    end

    it "forwards a block from run through to provider.chat as the stream sink" do
      OmniAgent.configure { |config| config.default_provider = :test_provider }

      agent_class = Class.new(described_class)
      agent = agent_class.new
      allow(agent).to receive(:available_tools).and_return([])

      captured_stream = :not_set
      allow(agent.provider).to receive(:chat) do |messages:, tools: [], stream: nil, **_options|
        captured_stream = stream
        OmniAgent::Providers::Response.new(content: "ok", raw_response: {}, tool_calls: [])
      end

      sink = ->(event) {}
      agent.run("Hello", &sink)

      expect(captured_stream).to eq(sink)
    end

    it "emits a done event with the final response when generation completes" do
      OmniAgent.configure { |config| config.default_provider = :test_provider }

      agent_class = Class.new(described_class)
      agent = agent_class.new
      allow(agent).to receive(:available_tools).and_return([])

      final_response = OmniAgent::Providers::Response.new(content: "done", raw_response: {}, tool_calls: [])
      allow(agent.provider).to receive(:chat).and_return(final_response)

      events = []
      result = agent.run("Hello") { |event| events << event }

      expect(result).to eq(final_response)
      expect(events.last).to be_a(OmniAgent::Streaming::Event)
      expect(events.last.done?).to be(true)
      expect(events.last.response).to eq(final_response)
    end

    it "emits tool_call and tool_result events around tool execution" do
      OmniAgent.configure { |config| config.default_provider = :test_provider }

      stub_const("StreamingTestTool", Class.new(OmniAgent::Tool) do
        def execute(**_args)
          "tool output"
        end
      end)

      agent_class = Class.new(described_class)
      agent = agent_class.new
      allow(agent).to receive(:available_tools).and_return([ StreamingTestTool ])

      response_with_tool_call = OmniAgent::Providers::Response.new(
        content: nil,
        raw_response: {},
        tool_calls: [ { id: "call_1", name: "StreamingTestTool", arguments: {} } ]
      )
      final_response = OmniAgent::Providers::Response.new(content: "done", raw_response: {}, tool_calls: [])

      allow(agent.provider).to receive(:chat).and_return(response_with_tool_call, final_response)

      events = []
      agent.run("Hello") { |event| events << event }

      expect(events.map(&:type)).to eq([ :tool_call, :tool_result, :done ])
      expect(events[0].tool_name).to eq("StreamingTestTool")
      expect(events[1].content).to eq("tool output")
      expect(events[1].error?).to be(false)
    end

    it "emits an errored tool_result event when a tool raises" do
      OmniAgent.configure { |config| config.default_provider = :test_provider }

      stub_const("FailingStreamingTool", Class.new(OmniAgent::Tool) do
        def execute(**_args)
          raise "boom"
        end
      end)

      agent_class = Class.new(described_class)
      agent = agent_class.new
      allow(agent).to receive(:available_tools).and_return([ FailingStreamingTool ])

      response_with_tool_call = OmniAgent::Providers::Response.new(
        content: nil,
        raw_response: {},
        tool_calls: [ { id: "call_1", name: "FailingStreamingTool", arguments: {} } ]
      )
      final_response = OmniAgent::Providers::Response.new(content: "done", raw_response: {}, tool_calls: [])

      allow(agent.provider).to receive(:chat).and_return(response_with_tool_call, final_response)

      events = []
      agent.run("Hello") { |event| events << event }

      tool_result_event = events.find(&:tool_result?)
      expect(tool_result_event.error?).to be(true)
      expect(tool_result_event.content).to match(/Error executing tool: boom/)
    end

    it "#stream returns a Streaming::Proxy that forwards the block to a run alias" do
      OmniAgent.configure { |config| config.default_provider = :test_provider }

      agent_class = Class.new(described_class) do
        run_aliases :ask
      end
      agent = agent_class.new
      allow(agent).to receive(:available_tools).and_return([])

      final_response = OmniAgent::Providers::Response.new(content: "done", raw_response: {}, tool_calls: [])
      allow(agent.provider).to receive(:chat).and_return(final_response)

      expect(agent.stream).to be_a(OmniAgent::Streaming::Proxy)

      events = []
      result = agent.stream.ask("Hello") { |event| events << event }

      expect(result).to eq(final_response)
      expect(events).not_to be_empty
      expect(events.last.done?).to be(true)
    end
  end
end
