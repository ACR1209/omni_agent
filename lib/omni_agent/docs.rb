module OmniAgent
  # The plain-Markdown documentation bundled in the gem's docs/ directory, so
  # coding agents working in a host app can read it offline. Generated from
  # omniagent-docs/ with `bundle exec rake docs:sync`.
  module Docs
    ROOT = File.expand_path("../../docs", __dir__)

    class << self
      def root
        ROOT
      end

      # Page names relative to the docs root, without the .md extension
      # (e.g. "tools", "mcp/authentication").
      def pages
        Dir.glob("**/*.md", base: root).map { |path| path.delete_suffix(".md") }.sort
      end

      def path(page = "index")
        name = page.to_s.strip.delete_prefix("/").delete_suffix(".md")
        return unless pages.include?(name)

        File.join(root, "#{name}.md")
      end

      def read(page = "index")
        file = path(page)
        File.read(file) if file
      end
    end
  end
end
