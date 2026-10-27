module OmniAgent
  module Loaders
    # Visible text only, with block elements on their own paragraphs. Uses
    # Loofah, which Rails already depends on.
    module HTML
      EXTENSIONS = %w[.html .htm .xhtml].freeze
      CONTENT_TYPES = %w[text/html application/xhtml+xml].freeze

      def self.handles?(filename:, content_type:)
        Loaders.matches?(filename, content_type, EXTENSIONS, CONTENT_TYPES)
      end

      def self.call(io, **)
        require "loofah"
        Loofah.document(io.read).to_text
      end
    end
  end
end
