module OmniAgent
  module Loaders
    # Text-based PDFs, via the optional pdf-reader gem. Scanned PDFs have no
    # text layer and come out empty; they need OCR, in a custom loader.
    module PDF
      EXTENSIONS = %w[.pdf].freeze
      CONTENT_TYPES = %w[application/pdf].freeze

      def self.handles?(filename:, content_type:)
        Loaders.matches?(filename, content_type, EXTENSIONS, CONTENT_TYPES)
      end

      def self.call(io, **)
        begin
          require "pdf-reader"
        rescue LoadError
          raise OmniAgent::MissingDependencyError, "Reading PDFs needs the pdf-reader gem: add `gem \"pdf-reader\"` to your Gemfile."
        end

        # pdf-reader pads text with spaces to keep the page layout.
        ::PDF::Reader.new(io).pages.map { |page| page.text.gsub(/[ \t]{2,}/, " ") }.join("\n\n")
      end
    end
  end
end
