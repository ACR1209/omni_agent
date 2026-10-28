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
          # config.document_loaders = {}               # extra has_chunks loaders, e.g. { docx: DocxLoader }

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

      class_option :skip_agents_md, type: :boolean, default: false,
                                    desc: "Don't point AGENTS.md (and CLAUDE.md, if present) at the bundled OmniAgent docs"

      AGENTS_MD_MARKER = "<!-- omni_agent:docs -->".freeze
      AGENTS_MD_SECTION = <<~MARKDOWN.freeze
        #{AGENTS_MD_MARKER}
        ## OmniAgent

        This app builds AI agents with the `omni_agent` gem. Its documentation ships
        inside the gem: run `bundle exec omni_agent docs` for the index (conventions,
        typical flows and every page), `bundle exec omni_agent docs <page>` to read a
        page, or `bundle exec omni_agent docs --path` for the directory. Read it before
        adding or changing agents (`app/agents/`), tools, MCP servers (`app/mcp_servers/`)
        or evals (`evals/`), and prefer the `rails generate omni_agent:*` generators.
      MARKDOWN

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

      def point_coding_agents_at_docs
        return if options[:skip_agents_md]

        add_docs_section("AGENTS.md", create: true)
        add_docs_section("CLAUDE.md", create: false)
      end

      def show_next_steps
        say "OmniAgent install complete."
        say "Next: rails generate omni_agent:agent SupportAgent --with-tools Tool1 Tool2"
        say "Expose tools to MCP clients: rails generate omni_agent:mcp_server Support --agents SupportAgent"
        say "Read the bundled docs: bundle exec omni_agent docs"
      end

      private

      def add_docs_section(file, create:)
        path = File.join(destination_root, file)

        if File.exist?(path)
          return say_status(:identical, file) if File.read(path).include?(AGENTS_MD_MARKER)

          append_to_file file, "\n#{AGENTS_MD_SECTION}"
        elsif create
          create_file file, AGENTS_MD_SECTION
        end
      end
    end
  end
end
