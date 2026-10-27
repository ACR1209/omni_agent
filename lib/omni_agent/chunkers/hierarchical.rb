module OmniAgent
  module Chunkers
    # Small child chunks for precise matching, each carrying its parent
    # section as context, so a search matches the child and the agent reads
    # the parent. Parents are Markdown sections of up to `size * 4` characters.
    module Hierarchical
      PARENT_SIZE_FACTOR = 4

      # ponytail: each child stores its parent's text, so parents are duplicated
      # per child; store parents once with a parent_id if storage matters.
      def self.call(text, size: 1000, overlap: 200)
        Markdown.call(text, size: size * PARENT_SIZE_FACTOR, overlap: overlap).flat_map do |parent|
          Recursive.call(parent[:content], size: size, overlap: overlap).map do |child|
            { content: child, context: parent[:content], metadata: parent[:metadata] }
          end
        end
      end
    end
  end
end
