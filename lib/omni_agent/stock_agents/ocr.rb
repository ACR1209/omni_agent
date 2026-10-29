require "pathname"
require "uri"

module OmniAgent
  module StockAgents
    # Reads photos, scans and PDFs with a vision model. `run` takes one source
    # or an array of them (pages of the same document, in order):
    #
    #   OCR.new.run(Pathname("receipt.jpg"))
    #   OCR.new.run([ Pathname("page1.png"), params[:page2], record.scan ])
    #   OCR.new.run([ "Only the totals table matters", URI("https://example.com/scan.png") ])
    #
    # Sources: Pathname, IO-like objects (File, StringIO, uploaded files),
    # ActiveStorage attachments/blobs, and http(s) URIs for images. Strings are
    # always instructions, never file paths, so user text can't read server files.
    class OCR < OmniAgent::StockAgent
      description "Extracts text and structured data from photos, scans and PDFs"
      use_model "gpt-4o"

      SIGNATURES = {
        "image/png" => "\x89PNG".b,
        "image/jpeg" => "\xFF\xD8\xFF".b,
        "image/gif" => "GIF8".b,
        "application/pdf" => "%PDF".b
      }.freeze

      # Default structured output. Host apps override it by subclassing
      # and declaring their own `output do ... end` block.
      output do
        string :text, description: "Full text of the document, in reading order"
      end

      private

      def build_messages(input:, history:)
        # [input].flatten, not Array(input): Array() splits an IO into its lines.
        super(input: input.is_a?(String) ? input : [ input ].flatten.map { |source| content_part(source) }, history: history)
      end

      def content_part(source)
        case source
        when String then { type: "text", text: source }
        when URI::HTTP then { type: "image_url", image_url: { url: source.to_s } }
        when Pathname then file_part(source.binread)
        else
          if source.respond_to?(:download) then file_part(source.download)
          elsif source.respond_to?(:read) then file_part(source.read.tap { source.rewind if source.respond_to?(:rewind) })
          else raise ArgumentError, "#{self.class.name} can't read a #{source.class}: pass a Pathname, IO, ActiveStorage attachment or URI"
          end
        end
      end

      def file_part(bytes)
        type = media_type(bytes)
        url = "data:#{type};base64,#{[ bytes ].pack('m0')}"
        return { type: "file", file: { filename: "document.pdf", file_data: url } } if type == "application/pdf"

        { type: "image_url", image_url: { url: url } }
      end

      def media_type(bytes)
        bytes = bytes.b
        return "image/webp" if bytes.start_with?("RIFF") && bytes[8, 4] == "WEBP"

        SIGNATURES.find { |_type, magic| bytes.start_with?(magic) }&.first ||
          raise(OmniAgent::Error, "#{self.class.name} reads PNG, JPEG, GIF, WEBP and PDF files only")
      end
    end
  end
end
