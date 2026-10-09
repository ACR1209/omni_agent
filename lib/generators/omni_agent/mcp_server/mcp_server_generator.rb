require "rails/generators/named_base"

module OmniAgent
  module Generators
    class McpServerGenerator < Rails::Generators::NamedBase
      desc "Creates an OmniAgent MCP server in app/mcp_servers and mounts it in config/routes.rb"

      class_option :tools,
                   type: :array,
                   default: [],
                   banner: "[ResearchAgent::Tools::GetWeather ...]",
                   desc: "Tool classes to expose"
      class_option :agents,
                   type: :array,
                   default: [],
                   banner: "[ResearchAgent ...]",
                   desc: "Agents whose tools are all exposed (tools_from)"
      class_option :path,
                   type: :string,
                   default: nil,
                   desc: "Mount path for the HTTP endpoint (default: /mcp/<name>)"

      def create_server_file
        create_file(File.join("app", "mcp_servers", "#{server_file_name}.rb"), server_template)
      end

      def mount_route
        route %(mount OmniAgent::MCP::RackApp.new("#{server_class_name}") => "#{mount_path}")
      end

      def show_next_steps
        say ""
        say "MCP server #{server_class_name} created."
        say ""
        say "Set a token, start the app and connect Claude Code over HTTP:"
        say "  #{token_env_var}=change-me bin/rails server"
        say "  claude mcp add --transport http #{server_slug} http://localhost:3000#{mount_path} --header \"Authorization: Bearer change-me\""
        say ""
        say "Or run it locally over stdio (no HTTP auth; see stdio_principal):"
        say "  claude mcp add #{server_slug} -- bundle exec omni_agent mcp #{server_class_name}"
      end

      private

      def server_class_name
        class_name.end_with?("Server") ? class_name : "#{class_name}Server"
      end

      def server_file_name
        server_class_name.underscore
      end

      def server_slug
        server_file_name.delete_suffix("_server").tr("/", "_")
      end

      def mount_path
        options[:path].presence || "/mcp/#{server_slug.dasherize}"
      end

      def token_env_var
        "#{server_slug.upcase}_MCP_TOKENS"
      end

      def server_template
        <<~RUBY
          class #{server_class_name} < OmniAgent::MCP::Server
            instructions "Tools exposed by #{server_class_name}."

          #{tool_lines.map { |line| "  #{line}" }.join("\n")}

            # Comma-separated list of accepted bearer tokens.
            authenticate :bearer, tokens: -> { ENV.fetch("#{token_env_var}", "").split(",") }

            # Hide tools per principal:
            # authorize_tool { |tool_class, principal| true }

            # Extra values merged into each tool's `context`:
            # context { |principal, request| { current_user: principal } }
          end
        RUBY
      end

      def tool_lines
        tools = Array(options[:tools]).map(&:strip).reject(&:empty?)
        agents = Array(options[:agents]).map(&:strip).reject(&:empty?)

        lines = []
        lines << "tools #{tools.join(', ')}" if tools.any?
        lines.concat(agents.map { |agent| "tools_from #{agent}" })
        lines << "# tools SomeAgent::Tools::SomeTool" if lines.empty?
        lines
      end
    end
  end
end
