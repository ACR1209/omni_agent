module OmniAgent
  module Chunkers
    # Splits on the coarsest boundary that fits: headings, then paragraphs,
    # lines, sentences and words, cutting mid-word only as a last resort.
    # Pieces are merged back up to `size` characters, and each chunk starts
    # with up to `overlap` characters of whole pieces from the one before.
    module Recursive
      # Zero-width, so every separator stays attached to its text.
      SEPARATORS = [
        /(?=^\#{1,6}\s)/, # Markdown headings
        /(?<=\n\n)/,      # paragraphs
        /(?<=\n)/,        # lines
        /(?<=[.!?]\s)/,   # sentences
        /(?<=\s)/         # words
      ].freeze

      def self.call(text, size: 1000, overlap: 200)
        merge(split(text.to_s, size, SEPARATORS), size, overlap)
      end

      def self.split(text, size, separators)
        return [ text ] if text.length <= size

        separator, *rest = separators
        return text.scan(/.{1,#{size}}/m) if separator.nil?

        text.split(separator).flat_map { |piece| split(piece, size, rest) }
      end

      def self.merge(pieces, size, overlap)
        chunks = []
        current = []

        pieces.each do |piece|
          if current.any? && length(current) + piece.length > size
            chunks << current.join
            current.shift while current.any? && (length(current) > overlap || length(current) + piece.length > size)
          end
          current << piece
        end
        chunks << current.join if current.any?

        chunks.map(&:strip).reject(&:empty?)
      end

      def self.length(pieces)
        pieces.sum(&:length)
      end

      private_class_method :split, :merge, :length
    end
  end
end
