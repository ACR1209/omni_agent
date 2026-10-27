module OmniAgent
  # ActiveRecord macro that turns a document into searchable chunks. Extended
  # into every model by the engine.
  #
  #   class Document < ApplicationRecord
  #     has_one_attached :file
  #     has_chunks :file
  #   end
  #
  #   Document.where(account_id: 1).semantic_search("refund policy") # => DocumentChunk records
  #
  # The source is an ActiveStorage attachment, a text column, rich text or
  # any method returning a String or IO. When it changes, OmniAgent::IngestJob
  # loads it into text (Loaders), splits it (Chunkers), embeds the chunks and
  # replaces the record's chunks. The chunk model (DocumentChunk by default)
  # belongs to the document and uses `has_embedding :content`.
  module Chunkable
    EMBED_BATCH_SIZE = 100

    def has_chunks(source, as: :auto, chunker: :recursive, size: 1000, overlap: 200, class_name: "#{name}Chunk", later: true)
      raise ArgumentError, "has_chunks size: must be a positive Integer" unless size.is_a?(Integer) && size.positive?
      raise ArgumentError, "has_chunks overlap: must be between 0 and size:" unless overlap.is_a?(Integer) && overlap >= 0 && overlap < size
      raise ArgumentError, "has_chunks later: must be true, false or a Hash of job options" unless [ true, false ].include?(later) || later.is_a?(Hash)
      raise ArgumentError, "#{name} already uses has_embedding. A model uses has_embedding or has_chunks, not both." if respond_to?(:embedding_options)

      Chunkers.fetch(chunker)
      Loaders.fetch(as) unless as.to_s == "auto"

      class_attribute :chunk_options, instance_writer: false
      self.chunk_options = {
        source: source.to_sym,
        loader: as,
        chunker: chunker,
        size: size,
        overlap: overlap,
        later: later != false,
        job_options: later.is_a?(Hash) ? Embeddable.validate_job_options!(later, "later:") : {}
      }

      has_many :chunks, -> { order(:position) }, class_name: class_name, dependent: :delete_all

      extend ClassMethods
      include InstanceMethods

      validate :validate_chunk_source_type, unless: -> { as.to_s == "auto" }
      before_save :remember_chunk_source_change
      after_commit :ingest_changed_chunks, on: %i[create update], if: -> { @chunk_source_changed }
    end

    module ClassMethods
      # The closest chunks of the records in the current scope. Chunks that
      # share a parent section (hierarchical) count once.
      def semantic_search(query, limit: 5)
        reflection = reflect_on_association(:chunks)
        # ponytail: fetches 3x the limit so merged siblings still fill it; raise if hierarchical results come up short.
        hits = reflection.klass.where(reflection.foreign_key => all.select(primary_key)).semantic_search(query, limit: limit * 3)

        hits.uniq { |chunk| chunk.try(:context) ? [ chunk[reflection.foreign_key], chunk.context ] : chunk.id }.first(limit)
      end

      # How a `searches` tool shows a chunk: its document, heading path and
      # text, or its parent section for hierarchical chunks.
      def format_search_chunk(chunk)
        label = [ "#{name}##{chunk[reflect_on_association(:chunks).foreign_key]}", *chunk.try(:metadata)&.dig("headings") ]
        "[#{label.join(' › ')}] #{chunk.try(:context) || chunk.content}"
      end

      # Ingests records that have no chunks yet, or every record with force: true.
      def ingest_all(force: false)
        (force ? all : all.where.missing(:chunks)).find_each(&:ingest!)
      end
    end

    module InstanceMethods
      # Loads, splits and embeds the source, then replaces this record's
      # chunks. Chunks whose text didn't change keep their vector, so
      # re-ingesting an edited document only embeds what's new.
      def ingest!
        chunk_class = chunks.klass
        column = chunk_class.try(:embedding_options)&.dig(:column)
        raise OmniAgent::Error, "#{chunk_class.name} needs `has_embedding :content` to store chunk vectors." unless column

        pieces = chunk_pieces
        vectors = chunks.where.not(column => nil).pluck(:content, column).to_h
        (pieces.map { |piece| piece[:content] }.uniq - vectors.keys).each_slice(EMBED_BATCH_SIZE) do |batch|
          vectors.merge!(batch.zip(OmniAgent.embed(batch)).to_h)
        end

        attributes = %i[content context metadata] & chunk_class.column_names.map(&:to_sym)
        foreign_key = self.class.reflect_on_association(:chunks).foreign_key
        rows = pieces.each_with_index.map do |piece, position|
          piece.slice(*attributes).merge(foreign_key => id, position: position, column => vectors[piece[:content]])
        end

        transaction do
          chunks.delete_all
          chunk_class.insert_all!(rows) if rows.any?
        end
        chunks.reset
        rows.size
      end

      # The source as clean text, or nil when there's nothing to read.
      def chunk_source_text
        value = public_send(chunk_options[:source])
        return if value.blank?

        if value.respond_to?(:attached?)
          value.blob.open { |file| Loaders.load(file, as: chunk_options[:loader], filename: value.filename.to_s, content_type: value.content_type) }
        elsif value.respond_to?(:to_plain_text)
          value.to_plain_text
        else
          Loaders.load(value.respond_to?(:read) ? value : StringIO.new(value.to_s), as: chunk_options[:loader])
        end
      end

      private

      def chunk_pieces
        text = chunk_source_text
        return [] if text.blank?

        Chunkers.chunk(text, chunker: chunk_options[:chunker], size: chunk_options[:size], overlap: chunk_options[:overlap])
      end

      def chunk_attachment_changed?
        respond_to?(:attachment_changes) && attachment_changes.key?(chunk_options[:source].to_s)
      end

      def remember_chunk_source_change
        source = chunk_options[:source].to_s
        # Other sources (rich text, methods) can't tell; ingest! re-embeds only changed chunks.
        @chunk_source_changed = if self.class.try(:reflect_on_attachment, source) then chunk_attachment_changed?
        elsif has_attribute?(source) then will_save_change_to_attribute?(source)
        else true
        end
      end

      def ingest_changed_chunks
        @chunk_source_changed = false
        upload_pending_attachment
        return ingest! unless chunk_options[:later]

        job_options = OmniAgent.configuration.embedding_job_options.merge(chunk_options[:job_options])
        OmniAgent::IngestJob.set(**job_options).perform_later(self)
      rescue OmniAgent::UnsupportedDocumentError => e
        logger&.warn("[OmniAgent] Skipped chunking #{self.class.name}##{id}: #{e.message}")
      end

      # ActiveStorage uploads in its own after_commit, which runs after this one
      # when has_chunks is declared first. Upload now, the way it does; it then
      # finds nothing left to upload.
      def upload_pending_attachment
        source = chunk_options[:source].to_s
        attachment_changes.delete(source).upload if chunk_attachment_changed? && attachment_changes[source].respond_to?(:upload)
      end

      # An enforced loader (as: :pdf) rejects other files at save, instead of
      # failing later in the job.
      def validate_chunk_source_type
        loader = Loaders.fetch(chunk_options[:loader])
        attachment = public_send(chunk_options[:source])
        return unless loader.respond_to?(:handles?) && chunk_attachment_changed? && attachment.attached?
        return if loader.handles?(filename: attachment.filename.to_s, content_type: attachment.content_type)

        errors.add(chunk_options[:source], "must be a #{chunk_options[:loader].to_s.upcase} file")
      end
    end
  end
end
