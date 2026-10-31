# OmniAgent

OmniAgent is a Rails engine gem for building application-native AI agents with tools.
It provides a small DSL to define agents, model/provider settings, prompt templates,
tool schemas, and generation lifecycle callbacks.

## What It Includes

- `OmniAgent::Agent` runtime with provider abstraction and tool-calling loop
- `OmniAgent::Tool` DSL with JSON-schema-style input definitions
- Structured, validated agent output declared with the same DSL as tool input
- Stock agents: ready-made agents shipped with the gem that projects subclass and customize
- Prompt composition from ERB files in `app/agents/<agent_name>/`
- Agent callbacks (`before_generation`, `after_generation`)
- Agent and tool tags to support filtering strategies
- OpenAI provider integration out of the box, plus an Ollama provider for local models
- RAG: `has_embedding` models, `has_chunks` documents (PDF, Markdown, HTML) and `searches` tools over pgvector, sqlite-vec, MariaDB or Meilisearch
- MCP server support: expose tools and whole agents to Claude Code, Claude Desktop, Cursor and other MCP clients
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

The `ollama` provider also depends on the `openai` gem — it talks to Ollama's OpenAI-compatible endpoint, so no separate gem is needed.

Then run:

```bash
bundle install
```

## Quick Start

1. Install base directories and the initializer:

```bash
bundle exec rails generate omni_agent:install
```

This also adds an OmniAgent section to `AGENTS.md` (and `CLAUDE.md`, if present) that points coding agents at the bundled docs. Pass `--skip-agents-md` to leave those files alone.

2. Generate an agent scaffold:

```bash
bundle exec rails generate omni_agent:agent ResearchAgent --model gpt-4.1-mini --with-tools WeatherLookup Summarize
```

3. Add your API key in `.env`:

```dotenv
OPENAI_ACCESS_TOKEN=your_api_key_here
```

To use Ollama instead, set `config.default_provider = :ollama` (see below) and, if needed, override its endpoint/model:

```dotenv
OLLAMA_HOST=http://localhost:11434   # defaults to this
OLLAMA_MODEL=llama3.1                # defaults to this; pick a tool-calling-capable model
OLLAMA_API_KEY=ollama                # unused by Ollama, but required by the openai client
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

## Structured Output

Declare an `output` block, using the same DSL as tool `input`, to get a validated object back instead of free text:

```ruby
class InvoiceAgent < OmniAgent::Agent
	output do
		string :invoice_number
		number :total, min: 0
		enum :currency, values: %w[USD EUR]
	end
end

InvoiceAgent.new.run(invoice_text).structured_output
# => { invoice_number: "A-1042", total: 120.5, currency: "USD" }
```

The schema is sent to the provider (as a `json_schema` `response_format` for OpenAI and Ollama), and the final answer is parsed and validated with the same rules as tool input. Invalid JSON or a schema mismatch raises `OmniAgent::StructuredOutputError`.

## Stock Agents

Stock agents are ready-made agents shipped with the gem under `OmniAgent::StockAgents`. Subclass one in your app and declare the output you need; the subclass keeps the stock prompt, model and tools:

```bash
rails generate omni_agent:stock_agent InvoiceOcr --from=ocr --fields=invoice_number:string total:number
```

```ruby
class InvoiceOcr < OmniAgent::StockAgents::OCR
	output do
		string :invoice_number
		number :total
	end
end

InvoiceOcr.new.run([ Pathname("page1.jpg"), Pathname("page2.jpg") ]).structured_output
```

The OCR stock agent reads images and PDFs from paths, uploaded files, ActiveStorage attachments or URLs, one at a time or several pages together.

The Classifier stock agent sorts text into labels you declare; it builds the output schema and prompt from them. Pass `multiple: true` to get every label that applies:

```bash
rails generate omni_agent:stock_agent TicketTriage --from=classifier --labels billing bug feature
```

```ruby
class TicketTriage < OmniAgent::StockAgents::Classifier
	labels billing: "Payments, invoices, refunds",
	       bug: "Something in the product is broken",
	       feature: "A request for new functionality"
end

TicketTriage.new.run("I was charged twice").structured_output
# => { label: "billing", confidence: 0.93, reason: "Mentions a duplicate charge" }
```

To add a stock agent to the gem itself, run `bin/rake "stock_agent:new[name]"` from the gem repository.

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

`.stream` must come before the call (`.stream.run(...)`, not `.run(...).stream`) — without it, or without a block, behavior is unchanged and the same `Response` is returned either way. Only the `openai`, `ollama`, and `mock` providers stream today. See [Streaming Responses](omniagent-docs/docs/agent/streaming.mdx) for the full event reference.

## RAG

Make a model searchable and give an agent a search tool for it:

```bash
rails generate omni_agent:embeddings Document title content   # migration + has_embedding
bin/rails db:migrate
bin/rails "omni_agent:embeddings:backfill[Document]"
```

```ruby
class Document < ApplicationRecord
	has_embedding :title, :content   # embedded on save via OmniAgent.embed
end

class SupportAgent < OmniAgent::Agent
	searches Document, scope: ->(context) { where(account_id: context[:account_id]) }
end
```

Vectors are stored with [neighbor](https://github.com/ankane/neighbor) on Postgres (pgvector), SQLite (sqlite-vec) or MariaDB. Models using meilisearch-rails work with `searches` as they are, and so does any object with a `semantic_search(query, limit:)` method. For files and long text, `has_chunks` splits them into searchable chunks:

```bash
rails generate omni_agent:chunks Document file   # DocumentChunk model + has_chunks
```

```ruby
class Document < ApplicationRecord
	has_one_attached :file
	has_chunks :file   # PDF, Markdown, HTML or text, detected per file
end
```

See [RAG](omniagent-docs/docs/rag.mdx) for the options, loaders, chunkers, Meilisearch setup and embedding configuration.

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

## MCP Servers

Expose your tools (and whole agents) to MCP clients such as Claude Code, Claude Desktop and Cursor. The protocol is implemented natively; no extra gem is needed.

```bash
rails generate omni_agent:mcp_server Support --with-tools LookupOrder --agents SupportAgent
```

```ruby
# app/mcp_servers/support_server.rb
class SupportServer < OmniAgent::MCP::Server
	instructions "Tools for the support team."

	# Tools in app/mcp_servers/support_server/tools/ (SupportServer::Tools::*) are added automatically.
	# Reuse existing tools and agents too:
	tools ResearchAgent::Tools::GetWeather
	tools_from SupportAgent
	expose_agent ResearchAgent, as: :research, description: "Ask the research agent", forward: [ :current_user ]

	authenticate :bearer, tokens: -> { ENV.fetch("SUPPORT_MCP_TOKENS", "").split(",") }
	# or: authenticate { |request| User.find_by(api_token: request.bearer_token) }
	# or OAuth 2.1 (MCP authorization spec), with tokens from your authorization server:
	# authenticate :oauth, resource: "https://app.example.com/mcp/support",
	#                      authorization_servers: "https://auth.example.com",
	#                      jwks_uri: "https://auth.example.com/.well-known/jwks.json"

	authorize_tool { |tool_class, principal| !tool_class.tags.include?(:admin) }
	context { |principal, _request| { current_user: principal } }
end
```

```ruby
# config/routes.rb -- Streamable HTTP (stateless, POST only)
mcp_server :support                        # SupportServer at /mcp/support
mcp_server :billing, path: "/internal/mcp"
# or mount every server in app/mcp_servers at /mcp/<name>:
mcp_servers
```

```bash
# stdio, for local clients
bundle exec omni_agent mcp SupportServer

claude mcp add --transport http support http://localhost:3000/mcp/support --header "Authorization: Bearer $TOKEN"
claude mcp add support -- bundle exec omni_agent mcp SupportServer
```

Tools can declare MCP-only hints with `title "Get weather"` and `annotations read_only: true, destructive: false, idempotent: true, open_world: true`. HTTP servers must declare `authenticate` (use `authenticate :none` to opt out on purpose). Requests from browser origins that are not in `allowed_origins` / `config.mcp_allowed_origins` are rejected.

## Configuration

`rails generate omni_agent:install` writes `config/initializers/omni_agent.rb` with every setting commented out at its default. Global defaults are set through `OmniAgent.configure`:

```ruby
OmniAgent.configure do |config|
	config.default_provider = :openai
	config.default_model = "gpt-4o-mini"
end
```

## Documentation for Coding Agents

The full documentation from https://omniagent.activetaskers.com/docs/intro ships inside the gem as plain Markdown in `docs/`, so coding agents (Claude Code, Cursor, Codex...) working in your app can read it offline:

```bash
bundle exec omni_agent docs                     # index: conventions, typical flows and every page
bundle exec omni_agent docs mcp/authentication  # one page
bundle exec omni_agent docs --path              # directory holding the Markdown files
```

`docs/` is generated from `omniagent-docs/docs` by `bundle exec rake docs:sync`, which `rake build` runs first. It isn't committed, so a gem installed from git (`gem "omni_agent", github: ...`) doesn't include it; use the docs site instead.

## Running Tests

```bash
bundle exec rspec
```

## Contributing

Issues and pull requests are welcome.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
