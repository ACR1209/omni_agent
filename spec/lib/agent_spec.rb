require_relative "../spec_helper"
require_relative "../../lib/omni_agent"
require_relative "../../lib/omni_agent/agent"
require_relative "../../lib/omni_agent/errors"
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

      def chat(messages:, tools: [], **options)
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
end
