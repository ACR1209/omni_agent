# Changelog

All notable changes to this project will be documented in this file.

## [0.1.7](https://github.com/ACR1209/omni_agent/compare/omni_agent-v0.1.6...omni_agent/v0.1.7) (2026-06-22)


### Features

* add agent runtime with providers and tool schema ([8e58dc3](https://github.com/ACR1209/omni_agent/commit/8e58dc38c79fa688204a8b9ed1c3e31aa507ff76))
* add basic base and open ai providers ([b6df958](https://github.com/ACR1209/omni_agent/commit/b6df9580eecfd0843c14cb5f4d5351ca9b84d5a7))
* add class-level `with` method to prefill context and merge with run context ([653a7a5](https://github.com/ACR1209/omni_agent/commit/653a7a51caf64fa93dfd3c7827ecc77ae1a93bd0))
* add configuration management to OmniAgent with default provider setup ([22a8784](https://github.com/ACR1209/omni_agent/commit/22a878442f47ac9dd6e1e0d78aa6898960c7ebf5))
* add generators for agent and install tasks, enhance configuration with default model ([2f4b122](https://github.com/ACR1209/omni_agent/commit/2f4b122bcd137dd2887605ffd5a077230b22c1ff))
* add max tool iterations limit and corresponding error handling ([5177cee](https://github.com/ACR1209/omni_agent/commit/5177cee9c467ab14d12ae6eb6f08abd68749db45))
* add Mock provider with chat method and update registry ([3f1d0b0](https://github.com/ACR1209/omni_agent/commit/3f1d0b0ec43201fbb29064b6b8913cae1062d319))
* add raw_request to Response and update providers to include request details ([ec467e6](https://github.com/ACR1209/omni_agent/commit/ec467e69d4a02bfbd99cf8ba9e2f94a948cc06ef))
* add stops_generation functionality to Tool and implement handling in Agent ([cc436e9](https://github.com/ACR1209/omni_agent/commit/cc436e9b07cc7ceaf66e9bbdf0dfe63e46def242))
* add tags DSL for storing and normalizing tags in OmniAgent ([626df18](https://github.com/ACR1209/omni_agent/commit/626df187c5264ae3429126731a5c5216a92e5573))
* add tools base class ([a53e571](https://github.com/ACR1209/omni_agent/commit/a53e57146eddce1f9a9a3fb1dd93656fff34c5ab))
* autoload concerns files as top level ([63bdf5f](https://github.com/ACR1209/omni_agent/commit/63bdf5fe1d0e47d9a0608759deb00136c5477ec3))
* change agent_generator to reflect the new structure ([2394db8](https://github.com/ACR1209/omni_agent/commit/2394db8a07ba360a4433eceaa891684acd75b764))
* enforce exclusive use of provider and use_model in OmniAgent ([1c6456b](https://github.com/ACR1209/omni_agent/commit/1c6456badf415d2b6daf36e1afc2334e8866fd31))
* enhance agent functionality with run aliases and private lifecycle callbacks ([58797be](https://github.com/ACR1209/omni_agent/commit/58797bedbdbcc9844439945298a2d89831046785))
* enhance agents to utilize before_generation callbacks for context variables ([65e4d8c](https://github.com/ACR1209/omni_agent/commit/65e4d8c289ed7c3622a7dfc612937dd902e21d13))
* enhance array method to support nested object schemas and update related specs ([865fcf1](https://github.com/ACR1209/omni_agent/commit/865fcf131a9c3e561d9b7aad4c39aa2fb93cfa37))
* enhance chat options handling in OmniAgent by merging DSL and runtime options ([c8e4d4d](https://github.com/ACR1209/omni_agent/commit/c8e4d4d0d314a5b70d27bc1c718fd070d4db5a22))
* enhance OpenAI provider to handle tools in chat payload ([6d185f4](https://github.com/ACR1209/omni_agent/commit/6d185f4d8b11bbefd25f75991cd8f6ec6d2e9ca6))
* enhance response handling by adding generated_messages support and updating related methods ([49237d3](https://github.com/ACR1209/omni_agent/commit/49237d36369ccaad5582bcda407987e03fffb5c2))
* enhance response handling by returning full response object and adding answer method ([6b786a2](https://github.com/ACR1209/omni_agent/commit/6b786a2e7b839316a8c4d339ecd87613f6d3c0dc))
* enhance tool invocation to filter arguments and add stops_generation functionality ([eccb945](https://github.com/ACR1209/omni_agent/commit/eccb94549c088c1f7e9293159c9cda8d836193ab))
* **eval:** add OmniAgent::Eval framework for testing agent quality ([04f1f5b](https://github.com/ACR1209/omni_agent/commit/04f1f5be1384e951af1cddfbbea03e5298d63cd5))
* implement before and after generation callback support ([d1e4eb5](https://github.com/ACR1209/omni_agent/commit/d1e4eb5e45743d5b66f299b733ed29f6102eb642))
* implement message validation and history handling in agent and providers ([6a081d9](https://github.com/ACR1209/omni_agent/commit/6a081d9068083282907e8a2734d02ee946884081))
* implement retry logic for OpenAI provider and enhance configuration options ([ec039b0](https://github.com/ACR1209/omni_agent/commit/ec039b00791c325d81d6326652c027baebe17d7f))
* implement tags DSL for managing and normalizing tags in Agent and Tool classes ([1ee7dfe](https://github.com/ACR1209/omni_agent/commit/1ee7dfe41a9b9c615ebd13bf896655591b8dd193))
* initialize OmniAgent Rails engine with test app ([35f7e00](https://github.com/ACR1209/omni_agent/commit/35f7e00bae3c7d5ae8eed6d5197e555b833737b2))
* make agent file be in the same directory of it ([bc30da7](https://github.com/ACR1209/omni_agent/commit/bc30da7aa63cc25ef966f7d5c4faaa3fb3391077))
* refactor response handling and add tool call message builder in Agent ([b43142a](https://github.com/ACR1209/omni_agent/commit/b43142af357d8fbe7c402d83b9d2d00a0a98ae99))
* update omni_agent to version 0.1.2; enhance context handling in agent methods ([bb16757](https://github.com/ACR1209/omni_agent/commit/bb167571c9dbea29cdcede349e4843efaba3c73c))
* update tool call handling to stop generation after processing tool calls ([c703a41](https://github.com/ACR1209/omni_agent/commit/c703a41205d93ba05a7fc80c4fe19249ebb1cc81))


### Bug Fixes

* correct order of callback execution in run method ([c95fc0f](https://github.com/ACR1209/omni_agent/commit/c95fc0f95766781b323d1dc1708315f7b3153219))
* create agent file in actual expected structure ([54d08e5](https://github.com/ACR1209/omni_agent/commit/54d08e53f2ced7eedec2b5968535b7a414f924e9))
* force eager load of the error aliases ([9112fba](https://github.com/ACR1209/omni_agent/commit/9112fbaa44f830605b93a23fdfadc1b4183df869))
* improve provider resolution error handling ([5b986ea](https://github.com/ACR1209/omni_agent/commit/5b986eafdd12a8a552d312d787371d4517a23425))
* set Rails dependency version to &gt;= 7.0 in gemspec ([1b98015](https://github.com/ACR1209/omni_agent/commit/1b9801573745990920cd6df8fffd45e24bfd6109))
* update omni_agent version to 0.1.1 and adjust Rails dependency to &gt;= 7.0; refactor error classes into a module ([1c5885c](https://github.com/ACR1209/omni_agent/commit/1c5885c5a02cb16c6f9c74290f63cb620b62adb0))
* update tool invocation to use instance methods and stop_generation! ([b1cd068](https://github.com/ACR1209/omni_agent/commit/b1cd068e8a71c0f156a3526519107d2cb0362956))

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
