<!-- Generated from omniagent-docs/docs/supported-providers.mdx by `bundle exec rake docs:sync`. Do not edit by hand. -->
<!-- Online version: https://omniagent.activetaskers.com/docs/supported-providers -->

# Supported providers

This is a list of our currently supported providers.

- OpenAI
- Ollama
- Mock

If you need another integration you can open a PR for it!

## OpenAI

Requires the `openai` gem and an API key:

```dotenv
OPENAI_ACCESS_TOKEN=your_api_key_here
```

```ruby
provider :openai, model: "gpt-4o-mini"
```

## Ollama

Talks to a local (or remote) [Ollama](https://ollama.com) server via its OpenAI-compatible `/v1` endpoint. Depends on the `openai` gem too — no separate client library needed. Pick a tool-calling-capable model (e.g. `llama3.1`, `qwen2.5`) if your agent uses tools.

```ruby
provider :ollama, model: "llama3.1"
```

Configuration is via environment variables, all optional:

| Variable | Default | Purpose |
| --- | --- | --- |
| `OLLAMA_HOST` | `http://localhost:11434` | Base URL of the Ollama server (the provider appends `/v1`) |
| `OLLAMA_MODEL` | `llama3.1` | Default model when none is passed to `provider`/`use_model` |
| `OLLAMA_EMBEDDING_MODEL` | `nomic-embed-text` | Default model for [`OmniAgent.embed`](rag.md#embeddings) |
| `OLLAMA_API_KEY` | `ollama` | Sent as the bearer token; Ollama ignores it, but the `openai` client requires a non-nil value |

Streaming, tool-calling and embeddings all work the same as the OpenAI provider (Ollama subclasses it and only overrides client construction and defaults).

## Mock

Returns a canned response without making network calls. Useful for tests. `embed` returns deterministic vectors derived from the text, so the same text always gets the same vector.
