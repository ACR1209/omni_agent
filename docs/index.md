# OmniAgent Documentation

Offline copy of https://omniagent.activetaskers.com/docs/intro, bundled with the `omni_agent` gem so coding
agents (Claude Code, Cursor, Codex...) can learn how the gem works from inside
a project that depends on it. Every page is plain Markdown; links between
pages are relative.

Locate these files from a host app with:

```bash
bundle exec omni_agent docs          # print this index
bundle exec omni_agent docs tools    # print one page (path without .md)
bundle exec omni_agent docs --path   # print the directory holding these files
```

## Conventions at a Glance

OmniAgent is convention over configuration: classes are discovered from
where they live, so put files where the generators put them.

| What | Where | Class |
| --- | --- | --- |
| Global settings | `config/initializers/omni_agent.rb` (written by `omni_agent:install`) | `OmniAgent.configure` |
| Agent | `app/agents/<name>.rb` | `<Name> < OmniAgent::Agent` |
| Agent system prompt | `app/agents/<name>/prompt.md.erb` | |
| Entrypoint prompt | `app/agents/<name>/<entrypoint>.md.erb` | |
| Agent tool | `app/agents/<name>/tools/<tool>.rb` | `<Name>::Tools::<Tool> < OmniAgent::Tool` |
| MCP server | `app/mcp_servers/<name>_server.rb` | `<Name>Server < OmniAgent::MCP::Server` |
| MCP server tool | `app/mcp_servers/<name>_server/tools/<tool>.rb` | `<Name>Server::Tools::<Tool>` |
| Eval | `evals/<name>_eval.rb` | `< OmniAgent::Eval` |

Prefer the generators (`rails generate omni_agent:agent`, `omni_agent:mcp_server`,
`omni_agent:stock_agent`, `omni_agent:eval`, `omni_agent:embeddings`,
`omni_agent:chunks`) over writing these files by hand.
See [Generators](generators.md).

## Typical Flows

* **Build an agent:** [Introduction](intro.md) → [Tools](tools.md) →
  [Run Entrypoints](agent/run-entrypoints.md) → [Structured Output](agent/structured-output.md).
* **Pick a provider or model:** [Supported Providers](supported-providers.md),
  [Configuration](configuration.md), [Change an Agent's Provider or Model](agent/provider.md).
* **Compose agents:** [Multi-Agent Delegation](agent/delegation.md),
  [Stock Agents](stock-agents.md).
* **Observe a run:** [Generation Callbacks](agent/callbacks.md),
  [Streaming Responses](agent/streaming.md).
* **Answer from your own data (RAG):** [Retrieval-Augmented Generation](rag.md)
  (`has_embedding`, `has_chunks` and the `searches` agent macro).
* **Test quality:** [Generating and Running Evals](evals/generating-and-running.md) →
  [Golden Sets](evals/golden-sets.md) → [Judge Provider](evals/judge-provider.md).
* **Expose tools to MCP clients:** [Defining MCP Servers](mcp/defining-servers.md) →
  [Authentication](mcp/authentication.md) → [Transports and Clients](mcp/transports.md).

## All Pages

### Core

* [Introduction](intro.md): **Omni Agent** is a gem focused on generating agentic code the Rails way.
* [Supported providers](supported-providers.md): This is a list of our currently supported providers.
* [Configuration](configuration.md): Omni Agent ships with sensible defaults but lets you configure global behavior through an initializer.
* [Tools](tools.md): Tools are how agents take action beyond generating text. Every tool is a small class that declares an input schema and implements `#execute`.
* [Generators](generators.md): Omni Agent ships seven Rails generators to scaffold your project.
* [Stock Agents](stock-agents.md): Stock agents are ready-made agents shipped with the gem under `OmniAgent::StockAgents`. They bring their own prompt, model settings and tools; your project subclasses one and declares the structured output it needs.
* [Retrieval-Augmented Generation (RAG)](rag.md): RAG lets an agent answer from your own data: it searches your records for the passages relevant to a question and gives them to the model. Omni Agent keeps the vectors in your own database (or Meilisearch) and turns any searchable model into an agent tool. Records are searched whole with `has_embedding`, and files or long text in chunks with `has_chunks`.

### Agents

Learn about agent specific features and functionalities.

* [Generation Callbacks](agent/callbacks.md): Agents support `before_generation` and `after_generation` callbacks, letting you hook into the lifecycle of a single `run` without overriding it yourself.
* [Run Entrypoints](agent/run-entrypoints.md): `OmniAgent::Agent` always exposes the low-level `run` method, but you'll usually call an agent through one of its higher-level entrypoints.
* [Change an Agent's Provider or Model](agent/provider.md): By default, agents use the configured `default_provider` and `default_model`. You can override these settings on a per-agent basis using one of the following DSL directives.
* [Multi-Agent Delegation](agent/delegation.md): `delegate_to` wraps another agent as a tool your agent's LLM can call, turning your agent into a **supervisor** that routes work to sub-agents. The delegated agent is defined and used like any other agent — a normal class under `app/agents/`, not a manual tool file.
* [Streaming Responses](agent/streaming.md): Any run entrypoint — `run`, an implicit entrypoint, or a `run_aliases` method — can stream its response by prefixing the call with `.stream` and passing a block. Without `.stream` (or without a block), behavior is completely unchanged.
* [Structured Output](agent/structured-output.md): Declare an `output` block to make an agent return a validated object instead of free text. It uses the same DSL as a tool's `input`.

### Evals

Test agent quality with deterministic assertions and LLM-as-judge scoring.

* [Generating and Running Evals](evals/generating-and-running.md): `OmniAgent::Eval` lets you test agent *quality*, not just correctness — deterministic assertions (tool calls, output matching) plus pluggable LLM-as-judge scoring.
* [Golden Sets](evals/golden-sets.md): For many input/expected-output pairs, load a dataset file instead of writing a `eval_case` per row.
* [Judge Provider](evals/judge-provider.md): `judge` resolves which provider grades the output, in this order.
* [Caching](evals/caching.md): Eval runs are cached by default, keyed on `(agent class, run_alias, input, context)`, and stored as JSON at `OmniAgent.configuration.eval_cache_path` (default `tmp/omni_agent_eval_cache.json`). Re-running the same case — e.g. while iterating on assertions — replays the cached output instead of calling the provider again, so you don't spend tokens testing the same case twice.

### MCP Servers

Expose your tools and agents to Claude Code, Claude Desktop, Cursor and other MCP clients.

* [Defining MCP Servers](mcp/defining-servers.md): The Model Context Protocol (MCP) lets AI clients such as Claude Code, Claude Desktop and Cursor call tools that live in your app. `OmniAgent::MCP::Server` turns the `OmniAgent::Tool` classes you already wrote for your agents — and the agents themselves — into an MCP server, with no extra gem.
* [Authentication](mcp/authentication.md): An MCP server mounted over HTTP lets anyone who can reach the URL run your tools. For that reason, **every server must declare `authenticate`**. A server without it raises `OmniAgent::MCPError` on the first HTTP request. To make a server public on purpose, write `authenticate :none`.
* [Transports and Clients](mcp/transports.md): OmniAgent supports both MCP transports.
