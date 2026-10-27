module OmniAgent
  module Chunkers
    # One chunk per Markdown section, with its heading path as metadata
    # ("headings" => ["Billing", "Refunds"]). Sections longer than `size`
    # are split further with Recursive. Text without headings is one section.
    module Markdown
      HEADING = /\A(\#{1,6})\s+(.+?)\s*#*\s*\z/
      FENCE = /\A\s*(```|~~~)/

      def self.call(text, size: 1000, overlap: 200)
        sections(text.to_s).flat_map do |headings, body|
          Recursive.call(body, size: size, overlap: overlap).map do |content|
            { content: content, metadata: headings.any? ? { "headings" => headings } : {} }
          end
        end
      end

      # [[headings, body], ...]: each section's body includes its own heading line.
      def self.sections(text)
        sections = [ [ [], +"" ] ]
        path = []
        in_fence = false

        text.each_line do |line|
          in_fence = !in_fence if line.match?(FENCE)
          heading = !in_fence && line.chomp.match(HEADING)

          if heading
            level = heading[1].length
            path = path.first(level - 1) + [ heading[2] ]
            sections << [ path, +"" ]
          end
          sections.last[1] << line
        end

        # A heading with nothing under it lives on in its subsections' paths.
        sections.reject { |headings, body| body.lines.drop(headings.any? ? 1 : 0).join.strip.empty? }
      end
    end
  end
end
