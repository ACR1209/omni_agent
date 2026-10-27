require "rails/generators"
require "fileutils"

module OmniAgent
  module Generators
    class InstallGenerator < Rails::Generators::Base
      desc "Creates OmniAgent base directories in app/agents and config/initializers/omni_agent.rb"

      INITIALIZER = <<~RUBY
        OmniAgent.configure do |config|
          # Every setting below shows its default. Uncomment to change it.

          # Agents
          # config.default_provider = :openai          # :openai, :ollama, :mock
          # config.default_model = "gpt-4o-mini"
          # config.max_tool_iterations = 10
          # config.max_delegation_depth = 5

          # Provider retries (rate limits, timeouts, 5xx), with exponential backoff
          # config.max_retries = 3
          # config.retry_base_delay = 0.5

          # Embeddings and RAG (has_embedding, searches)
          # config.embedding_provider = nil            # nil uses default_provider; use :mock in tests
          # config.embedding_model = nil               # nil uses the provider's default embedding model
          # config.embedding_job_options = {}          # for has_embedding later: true, e.g. { queue: :embeddings, priority: 10 }

          # Evals
          # config.eval_judge_provider = nil           # nil uses the evaluated agent's provider
          # config.eval_judge_model = nil
          # config.eval_cache_enabled = true
          # config.eval_cache_path = "tmp/omni_agent_eval_cache.json"

          # MCP servers
          # config.mcp_allowed_origins = []
          # config.mcp_max_request_bytes = 1_048_576
        end
      RUBY

      def create_agents_root
        agents_root = File.join(destination_root, "app", "agents")
        FileUtils.mkdir_p(agents_root)
        say_status :create, agents_root
      end

      def create_initializer
        path = File.join("config", "initializers", "omni_agent.rb")
        return say_status(:skip, path, :yellow) if File.exist?(File.join(destination_root, path))

        create_file path, INITIALIZER
      end

      def show_next_steps
        say "OmniAgent install complete."
        say "Next: rails generate omni_agent:agent SupportAgent --with-tools Tool1 Tool2"
        say "Expose tools to MCP clients: rails generate omni_agent:mcp_server Support --agents SupportAgent"
      end
    end
  end
end
