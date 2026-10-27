module OmniAgent
  module Loaders
    # Reads the file as-is, so the Markdown and hierarchical chunkers can
    # split on its headings.
    module Markdown
      EXTENSIONS = %w[.md .markdown .mdx].freeze
      CONTENT_TYPES = %w[text/markdown text/x-markdown text/x-web-markdown].freeze

      def self.handles?(filename:, content_type:)
        Loaders.matches?(filename, content_type, EXTENSIONS, CONTENT_TYPES)
      end

      def self.call(io, **)
        io.read
      end
    end
  end
end
