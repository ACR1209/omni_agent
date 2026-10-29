# Changelog

All notable changes to this project will be documented in this file.

## [0.2.0](https://github.com/ACR1209/omni_agent/compare/omni_agent/v0.1.11...omni_agent/v0.2.0) (2026-10-29)


### ⚠ BREAKING CHANGES

* **agent:** agent subclasses now inherit their parent's class-level settings: `provider`/model, `options`, tags, `before_generation`/ `after_generation` callbacks, tools, delegated tools and `output`. Apps with agent hierarchies (e.g. an `ApplicationAgent` base class) will pick up the parent's settings in every subclass.

### Features

* add OmniAgent.embed with configurable embedding provider and model ([19214df](https://github.com/ACR1209/omni_agent/commit/19214df320c33b60559ce4eca9e65d77aedbafb8))
* **agent:** add searches macro for semantic search tools ([764a756](https://github.com/ACR1209/omni_agent/commit/764a7568cc23c47bf42cea8719757d01fc8a3dbd))
* **agent:** add structured output and stock agents scaffold ([c23fb4a](https://github.com/ACR1209/omni_agent/commit/c23fb4a89f30dbb55916ce886deafafd65d7dba8))
* **agent:** address review feedback on structured output and inheritance ([143ce4b](https://github.com/ACR1209/omni_agent/commit/143ce4b5668edab2c06ed65071fd208846fd7457))
* **agent:** search has_chunks models with searches ([b794bb2](https://github.com/ACR1209/omni_agent/commit/b794bb2d1ef0cb94f45dfec674cf3670828987b7))
* **chunkable:** add has_chunks to chunk, embed and store documents ([414504b](https://github.com/ACR1209/omni_agent/commit/414504b3e5a26b7868a2fa1da938d48dd635518c))
* **chunkers:** add recursive, markdown and hierarchical chunkers ([2f8a97d](https://github.com/ACR1209/omni_agent/commit/2f8a97d8b9cc7016092a0233882960fff9f9270c))
* **docs:** bundle plain-Markdown docs in the gem for coding agents ([3cf1270](https://github.com/ACR1209/omni_agent/commit/3cf12705bef39064680463dc088322969de50518))
* **embeddable:** add has_embedding macro for ActiveRecord models ([32d716d](https://github.com/ACR1209/omni_agent/commit/32d716dded4e9820f841a6c89fa59b9a04281bc4))
* **embeddable:** configure embed job options globally and per model ([f4dcb39](https://github.com/ACR1209/omni_agent/commit/f4dcb39850fe53e5b80a408f548ae4b8cdea3bb4))
* **generators:** add omni_agent:chunks to set up a chunk model ([ad60360](https://github.com/ACR1209/omni_agent/commit/ad60360f630c33eae6d32f9d2acdd3b246caad45))
* **generators:** add omni_agent:embeddings generator ([5af765b](https://github.com/ACR1209/omni_agent/commit/5af765b454975b23f85903558d1832ba34ec32aa))
* **generators:** write a commented initializer in omni_agent:install ([c0f22aa](https://github.com/ACR1209/omni_agent/commit/c0f22aabe3affc4e17e60548288fa855cb968764))
* **loaders:** read PDF, HTML, Markdown and text documents with auto-detection ([c294323](https://github.com/ACR1209/omni_agent/commit/c2943237772e44983fa3bc62bb669d256ba2b4a3))
* **providers:** add embed for text embeddings ([519f169](https://github.com/ACR1209/omni_agent/commit/519f16968896c8f0580591e2e7af6b93e26df3ae))
* **stock_agents:** add OCR stock agent with image and PDF input ([b2683f3](https://github.com/ACR1209/omni_agent/commit/b2683f3532772e3d00a037e22d425164f8f785dd))
* **tasks:** add omni_agent:embeddings:backfill rake task ([2aa06f7](https://github.com/ACR1209/omni_agent/commit/2aa06f7c24895caa2eb1b7ce8a1493f783e0ffe9))


### Bug Fixes

* **agent:** separate search results with a rule ([bd018cc](https://github.com/ACR1209/omni_agent/commit/bd018cc09626dcfcde524fccdbcbc2fc8222052e))
* **chunkable:** lock the document while replacing its chunks ([5e695e6](https://github.com/ACR1209/omni_agent/commit/5e695e63384e57afbbd96571bbf59bd633a0bda7))
* **chunkable:** skip unreadable documents in ingest_all ([9b6b68d](https://github.com/ACR1209/omni_agent/commit/9b6b68dab3cb8686d3da7c46c0c4032015b2d4d7))
* **chunkers:** skip Markdown headings with nothing under them ([e228627](https://github.com/ACR1209/omni_agent/commit/e228627ac450902f33064f4dc1bd25c589b1f5bb))
* **embeddable:** discard embed jobs for deleted records ([1b69efc](https://github.com/ACR1209/omni_agent/commit/1b69efcba25e26419ffadaa9721f0c888b9a856a))
* **embeddable:** explain how to enable ActiveJob for later: true ([7f46446](https://github.com/ACR1209/omni_agent/commit/7f46446d993f036b4fa27fbb21035b65ae7bbae3))
* **engine:** load ActiveJob with the engine ([1392629](https://github.com/ACR1209/omni_agent/commit/1392629e4892a5f6ed1c38b5a2eb34cdddda7e00))
* **engine:** remove unused plugin scaffolding ([fa97033](https://github.com/ACR1209/omni_agent/commit/fa97033a96a7bff2ce4d4355008766d7fed7df89))
* **generators:** explain connection errors when detecting MariaDB ([a13a770](https://github.com/ACR1209/omni_agent/commit/a13a770ba607905fad8ee4d21fb168ed91b75429))
* **generators:** number migrations after the newest one ([01683a9](https://github.com/ACR1209/omni_agent/commit/01683a9e4efa7d05ea05e590615392ae78545180))
* **loaders:** drop scripts and styles anywhere in HTML ([972fa94](https://github.com/ACR1209/omni_agent/commit/972fa944fd224ace1c909ccbd1c4a57d254a81f7))
* **providers:** pass content-part arrays through to OpenAI ([22a5354](https://github.com/ACR1209/omni_agent/commit/22a535464b8053365a9fe4b8f1f850768e5a6472))

## [0.1.11](https://github.com/ACR1209/omni_agent/compare/omni_agent/v0.1.10...omni_agent/v0.1.11) (2026-10-15)


### Features

* **mcp:** add OAuth 2.1 authentication per the MCP authorization spec ([160c3d4](https://github.com/ACR1209/omni_agent/commit/160c3d47fb70272c58162359296c795a03b52219))


### Bug Fixes

* **mcp:** stop blocking requests while fetching the JWKS ([5074eb2](https://github.com/ACR1209/omni_agent/commit/5074eb2d939b2c1d6c365b15482cc9024f361527))

## [0.1.10](https://github.com/ACR1209/omni_agent/compare/omni_agent/v0.1.9...omni_agent/v0.1.10) (2026-10-09)


### Features

* **mcp:** expose tools and agents as MCP servers ([#40](https://github.com/ACR1209/omni_agent/issues/40)) ([db8dcb8](https://github.com/ACR1209/omni_agent/commit/db8dcb8776cc0baaed45112b61bc329f03d32181))

## [0.1.9](https://github.com/ACR1209/omni_agent/compare/omni_agent/v0.1.8...omni_agent/v0.1.9) (2026-07-12)


### Features

* **agent:** support streaming responses via stream sink ([7cf1fba](https://github.com/ACR1209/omni_agent/commit/7cf1fba4fa378c5cee7f464354f760506a0ff513))
* **docs:** add enum type for temperature unit in input schema ([d992658](https://github.com/ACR1209/omni_agent/commit/d99265836307ce8f863b060eff73c7acdbc8d2ff))
* **providers:** add Ollama provider via OpenAI-compat endpoint ([4ae92ad](https://github.com/ACR1209/omni_agent/commit/4ae92ad0f549119b43c2e8a7381f4f7245aa2f68))
* **tool:** add optional constraint validations and custom validate procs ([db8371a](https://github.com/ACR1209/omni_agent/commit/db8371a189f710e812c3c3ce15f200df1ba94902))
* **tool:** add polymorphic reference datatype ([1686bbb](https://github.com/ACR1209/omni_agent/commit/1686bbbf41932622a5537c335da8c41c68a73f73))
* **tool:** infer and validate enum value types in schema builder ([ceb3e78](https://github.com/ACR1209/omni_agent/commit/ceb3e780498caa1158e9fc8af3eb6e9b95c33ddb))
* **tool:** validate required and enum arguments on invoke ([543c6e0](https://github.com/ACR1209/omni_agent/commit/543c6e08f9c394b84c73bc5957aff7058e0fab19))


### Bug Fixes

* **lint:** add space inside empty block braces ([9116b3f](https://github.com/ACR1209/omni_agent/commit/9116b3ff82e9fab9824347515b4c1cd40a40785e))
* **spec:** redact OpenAI API key from recorded VCR cassettes ([53cecd5](https://github.com/ACR1209/omni_agent/commit/53cecd540b6dd52ddc5bf3da0550836fbfcfab88))

## [0.1.8](https://github.com/ACR1209/omni_agent/compare/omni_agent/v0.1.7...omni_agent/v0.1.8) (2026-07-07)


### Features

* implement multi-agent delegation with context forwarding and depth control ([e9b5497](https://github.com/ACR1209/omni_agent/commit/e9b5497b0af89172701bf4c5d93b8d5dccc77a26))

## [0.1.7](https://github.com/ACR1209/omni_agent/compare/omni_agent-v0.1.6...omni_agent/v0.1.7) (2026-06-22)


### Bug Fixes

* **docs:** use release-please block marker for version badge ([b83ca8d](https://github.com/ACR1209/omni_agent/commit/b83ca8dcad4acba976125b2a844e9c67d5a4df73))

## [Unreleased]

## [0.1.6] - 2026-06-21

### Added
- Added `OmniAgent::Eval` DSL for testing agent quality: `agent`, `eval_case`, `expect_tool_call`, `expect_output`, and LLM-as-judge `judge` assertions.
- Added `golden_set` support for generating eval cases from a YAML/JSON dataset file.
- Added `omni_agent:eval` rake task and `omni_agent:eval` generator for scaffolding and running evals.
- Added `mock_judge` provider for deterministic judge-assertion testing.
- Added `eval_judge_provider`/`eval_judge_model` configuration keys.
- Added `run_alias` to `eval_case`, so evals can target an agent's `run_aliases` method (different prompt file) instead of plain `#run`.
- Added `with:` to `input` for forwarding context into the agent run.
- Added eval result caching (keyed on agent class, run_alias, input, context) to avoid re-spending tokens on unchanged cases, configurable via `eval_cache_enabled`/`eval_cache_path`.
- Added `FRESH=1` env var and `fresh` task arg (`rake "omni_agent:eval[pattern,fresh]"`) to clear the eval cache before running, without manually deleting the cache file.
- Added `omni_agent` executable (`bundle exec omni_agent eval [pattern] [--fresh]`), an rspec-like CLI alternative to the `omni_agent:eval` rake task.

## [0.1.5] - 2026-06-18

### Added
- Added max tool iterations limit on the agent loop, with corresponding error raised when exceeded.
- Added retry logic to the OpenAI provider, configurable via `Configuration`.

### Fixed
- Improved provider resolution error handling for unknown providers.
- Forced eager load of error aliases to avoid Zeitwerk autoloading issues.

# [0.1.4] - 2026-06-16

### Fixed
- Change invoke method to an instance method instead of a class method, to actually catch invocations of the `stop_generation!` method.

### Changed
- Remove agent file from directory to prevent needing to change Zeitwerk initializer as Railtie wasn't allowing to change behaviour without it. 

### Added
- Add Railtie to project to handle concerns.
- Added docusaurus, the actual docs will be done later. 

## [0.1.3] - 2026-06-12

### Added
- Added `:mock` provider to be able to test `after_generation` and `before_generation` behaviour
- Added new DSL for tools `stops_generation` which signals to stop the chat flow once this tool is executed
- Added new instance methods for tools `stops_generation!` and `stops_generation?` that allow to stop the generation within the `execute` logic
- Added `raw_request` to the agent response, it includes the exact requests params sent to the provider
- Added `raw_response` to the agent response, it includes the exact response from the provider.
- Added `generated_messages` to the agent response, it contains all the messages generated by the agent and the user request.
- Added `history` as a context variable which are the messages to be sent to the provider.
- Added support for nested datatypes in the `array` schema for tools

## [0.1.2] - 2026-06-11

### Fixed
- Fixed Zeitwerk issue with `OmniAgent::Errors`

## [0.1.1] - 2026-06-09

### Changed
- Lowered Rails version needed.

## [0.1.0] - 2026-06-09

### Added
- Initial release of OmniAgent as a Rails engine for building application-native AI agents.
- Agent runtime with provider abstraction, tool-calling loop, callbacks, and prompt rendering.
- OpenAI provider support via the `openai` gem.
- Tool DSL with JSON schema generation.
- Rails generators and tasks for agent scaffolding.
- RSpec coverage for agent runtime, providers, tools, and integration flows.
