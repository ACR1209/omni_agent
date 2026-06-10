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
app/agents/research_agent/
	research_agent.rb
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
