<!-- Generated from omniagent-docs/docs/generators.mdx by `bundle exec rake docs:sync`. Do not edit by hand. -->
<!-- Online version: https://omniagent.activetaskers.com/docs/generators -->

# Generators

Omni Agent ships seven Rails generators to scaffold your project.

## Install Generator

```bash
rails generate omni_agent:install
```

Creates the `app/agents` root directory and `config/initializers/omni_agent.rb`, which lists every [configuration](configuration.md) setting commented out at its default. An existing initializer is left untouched. Run this once per application, right after installing the gem.

It also adds an OmniAgent section to `AGENTS.md` (created if missing) and to `CLAUDE.md` (only if it already exists). The section tells coding agents such as Claude Code, Cursor or Codex to read the documentation bundled with the gem:

```bash
bundle exec omni_agent docs                     # index: conventions, typical flows and every page
bundle exec omni_agent docs mcp/authentication  # one page
bundle exec omni_agent docs --path              # directory holding the Markdown files
```

Running the generator again doesn't duplicate the section. Pass `--skip-agents-md` to leave both files alone.

## Agent Generator

```bash
rails generate omni_agent:agent ResearchAgent --model gpt-4o-mini --with-tools WeatherLookup Summarize
```

Generates:

```text
app/agents/
├── research_agent.rb
└── research_agent/
    ├── prompt.md.erb
    └── tools/
        ├── weather_lookup.rb
        └── summarize.rb
```

### Options

* **`--model`**: Sets the model used in the generated `use_model` call. If omitted, the agent uses `OmniAgent.configuration.default_model`.
* **`--with-tools`**: Space-separated list of tool names to scaffold under `tools/`. Each is generated as a subclass of `OmniAgent::Tool` with an example `input` schema and `execute` method. If you pass `--with-tools` with no names, an `ExampleTool` is generated.

```bash
rails generate omni_agent:agent SupportAgent --with-tools
```

## Stock Agent Generator

```bash
rails generate omni_agent:stock_agent InvoiceOcr --from=ocr --fields=invoice_number:string total:number
```

Generates `app/agents/invoice_ocr.rb`, a subclass of the chosen [stock agent](stock-agents.md) with an `output` block, and an optional `app/agents/invoice_ocr/prompt.md.erb` for extra instructions.

### Options

* **`--from`** (required): Stock agent to build on, by its `stock_name` (see `OmniAgent::StockAgents.all`).
* **`--fields`**: Space-separated `name:type` output fields (`string`, `integer`, `number` or `boolean`). If omitted, an `example_field` is generated. Use the full [structured output DSL](agent/structured-output.md) in the generated file for enums, nested objects or optional fields.

## Eval Generator

```bash
rails generate omni_agent:eval ResearchAgent
```

Generates `evals/research_agent_eval.rb` with a starter `eval_case` for `ResearchAgent`. See [Generating and Running Evals](evals/generating-and-running.md), [Golden Sets](evals/golden-sets.md), [Judge Provider](evals/judge-provider.md), and [Caching](evals/caching.md).

## MCP Server Generator

```bash
rails generate omni_agent:mcp_server Support --with-tools LookupOrder RefundOrder --agents SupportAgent
```

Generates:

```text
app/mcp_servers/
├── support_server.rb
└── support_server/
    └── tools/
        ├── lookup_order.rb
        └── refund_order.rb
```

The server is protected by bearer tokens from `SUPPORT_MCP_TOKENS`. The generator also adds this route:

```ruby
mcp_server :support
```

If `config/routes.rb` already mounts every server with a bare `mcp_servers`, the generator skips the route because the new server is mounted automatically.

It then prints the commands to connect Claude Code over HTTP and stdio.

### Options

* **`--with-tools`**: Space-separated list of server tools to scaffold under `app/mcp_servers/<name>_server/tools/`. They are added to the server automatically. If you pass `--with-tools` with no names, an `ExampleTool` is generated.
* **`--tools`**: Existing tool classes (for example, agent tools) to expose with `tools`.
* **`--agents`**: Agents whose tools are all exposed with `tools_from`.
* **`--path`**: Mount path, written as `mcp_server :support, path: "..."`. Defaults to `/mcp/<name>`.

The `Server` suffix is added if you leave it out (`Support` → `SupportServer`). See [Defining MCP Servers](mcp/defining-servers.md).

## Embeddings Generator

```bash
rails generate omni_agent:embeddings Document title content
```

Adds an embedding column to the `Document` model and declares `has_embedding :title, :content` on it, so the model can be searched by agents with [`searches`](rag.md#searches). The migration matches your database: a pgvector `vector` column with a cosine index on Postgres, a `binary` column plus the sqlite-vec initializer on SQLite, a `vector` column on MariaDB. The vector size is detected by embedding one string with your configured model.

It then prints the commands to install the gems, migrate and backfill existing records.

### Options

* **`--backend`**: `pgvector`, `sqlite`, `mariadb` or `ruby`. Defaults to the one matching your database adapter. Plain MySQL is refused unless you pass `--backend=ruby`, which is [for small tables only](rag.md#ruby-fallback-small-tables-only).
* **`--dimensions`**: Vector size. Pass it when the embedding model can't be reached (offline, no API key).
* **`--column`**: Vector column name. Defaults to `embedding`.
* **`--later`**: Embed in a [background job](rag.md#background-embedding) after commit instead of during `save`.

## Chunks Generator

```bash
rails generate omni_agent:chunks Document file
```

Creates a `DocumentChunk` model and its table (with a vector column that matches your database, like the [embeddings generator](#embeddings-generator)) and declares `has_chunks :file` on `Document`, so its [documents are split and searched in chunks](rag.md#documents). If `file` is neither declared on the model nor a column, it's taken as an upload and `has_one_attached :file` is added too.

It then prints the commands to install the gems, migrate and ingest existing records.

### Options

* **`--as`**: A [loader](rag.md#loaders) to enforce (`pdf`, `html`, `markdown`, `text`). Defaults to detecting each file's format.
* **`--chunker`**: `recursive`, `markdown` or `hierarchical`. Defaults to `recursive`.
* **`--size`** / **`--overlap`**: Chunk size and overlap, in characters.
* **`--inline`**: Ingest right after commit instead of in a background job.
* **`--backend`** / **`--dimensions`**: Same as the [embeddings generator](#options-3).
