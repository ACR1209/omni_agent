require "active_support/core_ext/string/inflections"

module OmniAgent
  module MCP
    # Router helpers, included into ActionDispatch::Routing::Mapper by the engine.
    #
    #   mcp_server :support                        # SupportServer at /mcp/support
    #   mcp_server :support, path: "/internal/mcp" # custom path
    #   mcp_servers :support, :billing             # several at once
    #   mcp_servers                                # every app/mcp_servers/**/*_server.rb
    module Routing
      DEFAULT_PATH_PREFIX = "/mcp".freeze

      def mcp_server(name, path: nil, server: nil, as: nil)
        slug = OmniAgent::MCP::Routing.slug_for(name)
        server_name = server.is_a?(Class) ? server.name : (server || "#{slug}_server".camelize).to_s

        mount OmniAgent::MCP::RackApp.new(server_name) => (path || "#{DEFAULT_PATH_PREFIX}/#{slug.dasherize}"),
              as: (as || "#{slug.tr('/', '_')}_mcp_server")
      end

      def mcp_servers(*names, except: [], directory: nil)
        names = names.flatten
        names = OmniAgent::MCP::Routing.discover(directory || Rails.root.join("app", "mcp_servers")) if names.empty?
        excluded = Array(except).map { |name| OmniAgent::MCP::Routing.slug_for(name) }

        names.each do |name|
          mcp_server(name) unless excluded.include?(OmniAgent::MCP::Routing.slug_for(name))
        end
      end

      # :support, "support", "support_server", "SupportServer" -> "support"
      # "Admin::SupportServer", "admin/support" -> "admin/support"
      def self.slug_for(name)
        name.to_s.underscore.delete_suffix("_server")
      end

      # Server slugs for every *_server.rb file, without loading any code.
      # Skips files inside a server's own directory (e.g. support_server/tools/)
      # and abstract base servers named application_*.
      def self.discover(directory)
        root = Pathname.new(directory.to_s)
        return [] unless root.directory?

        Dir.glob(root.join("**", "*_server.rb").to_s).sort.filter_map do |file|
          relative = Pathname.new(file).relative_path_from(root).to_s.delete_suffix(".rb")
          *dirs, base = relative.split("/")

          next if dirs.any? { |dir| dir.end_with?("_server") }
          next if base.start_with?("application_")

          slug_for(relative)
        end
      end
    end
  end
end
