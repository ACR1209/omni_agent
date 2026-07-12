# OmniAgent

OmniAgent is a Rails engine gem for building application-native AI agents with tools.
It provides a small DSL to define agents, model/provider settings, prompt templates,
tool schemas, and generation lifecycle callbacks.

## What It Includes

- `OmniAgent::Agent` runtime with provider abstraction and tool-calling loop
- `OmniAgent::Tool` DSL with JSON-schema-style input definitions
- Prompt composition from ERB files in `app/agents/<agent_name>/`
- Agent callbacks (`before_generation`, `after_generation`)
- Agent and tool tags to support filtering strategies
- OpenAI provider integration out of the box
- Rake tasks and Rails generators for scaffolding

## Installation

Add these lines to your application's Gemfile:

```ruby
gem "omni_agent"
```

Add the provider you're using to the Gemfile as well:
```ruby
gem "openai"
```

Then run:

```bash
bundle install
```

## Quick Start

1. Install base directories:

```bash
bundle exec rails generate omni_agent:install
```

2. Generate an agent scaffold:

```bash
bundle exec rails generate omni_agent:agent ResearchAgent --model gpt-4.1-mini --with-tools WeatherLookup Summarize
```

3. Add your API key in `.env`:

```dotenv
OPENAI_ACCESS_TOKEN=your_api_key_here
```

4. Implement your agent prompt and optional tools under:

```text
app/agents/
	research_agent.rb
	research_agent/
		prompt.md.erb
		tools/
```

## Agent Example

```ruby
class ResearchAgent < OmniAgent::Agent
	use_model "gpt-4o-mini"

	before_generation :set_current_user

	def set_current_user
		@user = "Test User"
	end
end
```

## Tool Example

```ruby
module ResearchAgent::Tools
	class GetWeather < OmniAgent::Tool
		description "Get current weather for a city"
		tags :weather
		metadata category: :utility

		input do
			string :city, description: "City name"
		end

		def execute(city:)
			"Sunny in #{city}"
		end
	end
end
```

## Multi-Agent Delegation

`delegate_to` turns an agent into a supervisor: it wraps another agent class as a tool, so the supervisor's LLM can decide when to hand off to it. The delegated agent is a normal, independently defined agent (e.g. `app/agents/research_agent.rb`) — no manual tool file needed.

```ruby
class SupervisorAgent < OmniAgent::Agent
	use_model "gpt-4o"

	delegate_to ResearchAgent, as: :research,  description: "Look up factual info"
	delegate_to MathAgent,     as: :calculate, description: "Do arithmetic"
end
```

Each delegated agent runs in isolation (its own fresh instance, no shared context) and returns its final answer as the tool result. Delegation depth is capped by `OmniAgent.configuration.max_delegation_depth` (default `5`) to guard against runaway recursive delegation; exceeding it raises `OmniAgent::MaxDelegationDepthError`.

Pass `run_alias:` to call a `run_aliases` method (or any zero-arg run entrypoint) on the delegated agent instead of its default `#run` — useful when the sub-agent should render a different prompt file for delegated calls:

```ruby
class SupervisorAgent < OmniAgent::Agent
	delegate_to SupportAgent, as: :triage_ticket, run_alias: :triage
end
```

Pass `forward:` to share part (or all) of the supervisor's context with the delegated agent — an array of context keys, or `true` to forward everything. Omitted keys, and the default (`forward: []`), keep the delegated agent fully isolated:

```ruby
class SupervisorAgent < OmniAgent::Agent
	delegate_to ResearchAgent, as: :research, forward: [ :user, :locale ]
	delegate_to MathAgent,     as: :calculate, forward: true
end
```

## Streaming

Prefix any run entrypoint with `.stream` and pass a block to receive the response as it's generated instead of waiting for the full result:

```ruby
ResearchAgent.with(user_id: 42).stream.run("What's new?") do |event|
	case event.type
	when :text        then print event.text
	when :tool_call   then puts "\n[using #{event.tool_name}...]"
	when :tool_result then puts "[#{event.error? ? "failed" : "done"}]"
	when :done        then puts "\n---"
	end
end
```

`.stream` must come before the call (`.stream.run(...)`, not `.run(...).stream`) — without it, or without a block, behavior is unchanged and the same `Response` is returned either way. Only the `openai` and `mock` providers stream today. See [Streaming Responses](omniagent-docs/docs/agent/streaming.mdx) for the full event reference.

## Evals

`OmniAgent::Eval` lets you test agent quality: deterministic assertions (tool calls, output matching) and pluggable LLM-as-judge scoring.

```ruby
class ResearchAgentEval < OmniAgent::Eval
	agent ResearchAgent

	eval_case "answers weather question" do
		input "What's the weather in Paris?"
		expect_tool_call :get_weather, with: { city: "Paris" }
		expect_output to_include: "Paris"
	end

	eval_case "is polite" do
		input "Tell me a joke"
		judge "Is the response friendly and on-topic?", threshold: 0.7
	end

	eval_case "summarizes via the :summarize run alias" do
		run_alias :summarize
		input "Some long article text...", with: { tone: "casual" }
		expect_output to_include: "summary"
	end
end
```

* **`input text, with: {}`**: `with:` is forwarded as the agent's `context:`, bound to matching instance variables during the run (e.g. `with: { tone: "casual" }` sets `@tone`).
* **`run_alias`**: Targets a method defined via `run_aliases` (or any zero-arg run entrypoint) instead of plain `#run` — useful when that alias renders a different prompt file (`<method_name>.md.erb`).

Judge provider resolution order: explicit `provider:` kwarg on `judge` → `OmniAgent.configuration.eval_judge_provider`/`eval_judge_model` → the agent's own provider (zero-config default).

### Caching

Eval runs are cached by default, keyed on `(agent class, run_alias, input, context)`. Re-running the same case (e.g. iterating on assertions) replays the cached output instead of calling the provider again, saving tokens. Configure or disable it:

```ruby
OmniAgent.configure do |config|
	config.eval_cache_enabled = true # default
	config.eval_cache_path = "tmp/omni_agent_eval_cache.json" # default
end
```

Bypass the cache for a run (clears it before running, no manual file deletion needed):

```bash
bundle exec omni_agent eval evals/research_agent_eval.rb --fresh
```

Sample output:

```text
[PASS] mentions lorem
[FAIL] mentions something the mock never says
  - output "Lorem ipsum dolor sit amet, consectetur adipiscing elit." does not include "this never appears"

1/2 cases passed
```

Each case prints `[PASS]`/`[FAIL]` plus its name; failing cases list every unmet assertion's message. Exits non-zero if any case failed.

For many input/expected-output pairs, load a YAML/JSON dataset instead of writing a `case` per row:

```ruby
golden_set "evals/golden/research_agent.yml" do |row|
	expect_output to_include: row[:expected_output]
end
```

Scaffold an eval and run it:

```bash
bundle exec rails generate omni_agent:eval ResearchAgent

# run from your Rails app root, like running rspec
bundle exec omni_agent eval
bundle exec omni_agent eval evals/research_agent_eval.rb
bundle exec omni_agent eval evals/research_agent_eval.rb --fresh
```

There's also an equivalent `rake omni_agent:eval` task (`rake "omni_agent:eval[pattern,fresh]"`) if you'd rather not use the binstub.

Calls real LLM providers (cost, non-determinism) — deliberately **not** part of `bundle exec rspec` or CI.

## Configuration

Global defaults can be configured through `OmniAgent.configure`:

```ruby
OmniAgent.configure do |config|
	config.default_provider = :openai
	config.default_model = "gpt-4o-mini"
end
```

## Running Tests

```bash
bundle exec rspec
```

## Contributing

Issues and pull requests are welcome.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
