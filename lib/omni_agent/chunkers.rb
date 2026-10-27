module OmniAgent
  # Strategies that split text into chunks for `has_chunks`. A chunker is
  # anything that responds to `call(text, size:, overlap:)` and returns
  # Strings, or Hashes with :content and optional :context and :metadata.
  module Chunkers
    def self.registry
      {
        recursive: Recursive,
        markdown: Markdown,
        hierarchical: Hierarchical
      }
    end

    def self.fetch(chunker)
      return chunker if chunker.respond_to?(:call)

      registry.fetch(chunker.to_sym) do
        raise ArgumentError, "Unknown chunker #{chunker.inspect}. Use #{registry.keys.join(', ')}, or an object that responds to call."
      end
    end

    # Runs a chunker and normalizes its output to Hashes, dropping blank chunks.
    def self.chunk(text, chunker:, size:, overlap:)
      fetch(chunker).call(text, size: size, overlap: overlap).filter_map do |chunk|
        chunk = chunk.is_a?(Hash) ? chunk.to_h.transform_keys(&:to_sym) : { content: chunk.to_s }
        content = chunk[:content].to_s.strip
        { content: content, context: chunk[:context].presence, metadata: chunk[:metadata] || {} } unless content.empty?
      end
    end
  end
end
