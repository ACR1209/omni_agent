module OmniAgent
  # Strategies that turn a document into text for `has_chunks`. A loader is
  # anything that responds to `call(io, filename:, content_type:)` and returns
  # a String. Loaders that also answer `handles?(filename:, content_type:)`
  # take part in auto-detection; register your own in
  # `config.document_loaders` (they're tried before the built-in ones).
  module Loaders
    # Content types that say nothing about the format, so detection skips them.
    GENERIC_CONTENT_TYPES = [ "application/octet-stream", "binary/octet-stream" ].freeze
    SNIFF_BYTES = 8192

    def self.registry
      built_in = { pdf: PDF, html: HTML, markdown: Markdown, text: Text }
      OmniAgent.configuration.document_loaders.transform_keys(&:to_sym).merge(built_in) { |_name, custom, _built_in| custom }
    end

    def self.fetch(loader)
      return loader if loader.respond_to?(:call)

      registry.fetch(loader.to_sym) do
        raise ArgumentError, "Unknown loader #{loader.inspect}. Use :auto, #{registry.keys.join(', ')}, or an object that responds to call."
      end
    end

    # Reads a document into clean text, with the given loader or, for
    # as: :auto, the first one that handles its filename or content type.
    # Without either, it looks at the first bytes: PDF and HTML are
    # recognized, anything else without NUL bytes is read as text.
    def self.load(io, as: :auto, filename: nil, content_type: nil)
      content_type = nil if GENERIC_CONTENT_TYPES.include?(content_type)
      loader = as.to_s == "auto" ? detect(io, filename: filename, content_type: content_type) : fetch(as)

      clean(loader.call(io, filename: filename, content_type: content_type))
    end

    def self.detect(io, filename:, content_type:)
      loader = registry.values.find { |candidate| candidate.respond_to?(:handles?) && candidate.handles?(filename: filename, content_type: content_type) }
      loader || sniff(io) || raise(
        OmniAgent::UnsupportedDocumentError,
        "Can't read #{filename || 'this document'} (#{content_type || 'unknown type'}). " \
        "Pass `as:` a loader, or register one in config.document_loaders."
      )
    end

    def self.sniff(io)
      sample = io.read(SNIFF_BYTES).to_s
      io.rewind

      if sample.start_with?("%PDF-") then PDF
      elsif sample.match?(/\A\s*<(!doctype html|html)/i) then HTML
      elsif !sample.include?("\0") then Text
      end
    end

    # Fixes encodings and strips what databases and chunkers trip on:
    # invalid bytes, NULs (Postgres rejects them), CRLFs and runs of blank lines.
    def self.clean(text)
      text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("").delete("\u0000")
          .gsub(/\r\n?/, "\n").gsub(/[ \t]+$/, "").gsub(/\n{3,}/, "\n\n").strip
    end

    def self.matches?(filename, content_type, extensions, content_types)
      content_types.include?(content_type.to_s.split(";").first) || extensions.include?(File.extname(filename.to_s).downcase)
    end

    private_class_method :detect, :sniff, :clean
  end
end
