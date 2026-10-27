module OmniAgent
  module Loaders
    module Text
      EXTENSIONS = %w[.txt .text .csv .log].freeze

      def self.handles?(filename:, content_type:)
        content_type.to_s.start_with?("text/") || Loaders.matches?(filename, content_type, EXTENSIONS, [])
      end

      def self.call(io, **)
        io.read
      end
    end
  end
end
