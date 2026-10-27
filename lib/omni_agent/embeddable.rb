module OmniAgent
  # ActiveRecord macro that keeps an embedding of some attributes up to date
  # and adds `semantic_search`. Extended into every model by the engine.
  #
  #   class Document < ApplicationRecord
  #     has_embedding :title, :content
  #   end
  #
  #   Document.where(account_id: 1).semantic_search("refund policy", limit: 5)
  #
  # The default backend is the neighbor gem (pgvector, sqlite-vec, MariaDB).
  # `later: true` embeds in OmniAgent::EmbedJob after commit instead; pass a
  # Hash (`later: { queue: :embeddings }`) to override the global
  # `embedding_job_options` for this model.
  #
  # `using: :ruby` stores vectors in a JSON column and ranks them in Ruby;
  # it loads every row per search, so it only suits small tables.
  module Embeddable
    BACKENDS = %i[neighbor ruby].freeze
    # The options ActiveJob's `set` takes, for `later:` and embedding_job_options.
    JOB_OPTIONS = %i[queue priority wait wait_until].freeze

    def self.validate_job_options!(options, setting)
      unknown = options.keys.map(&:to_sym) - JOB_OPTIONS
      return options.to_h.transform_keys(&:to_sym) if unknown.empty?

      raise ArgumentError, "Unknown #{setting} option #{unknown.first.inspect}. Use #{JOB_OPTIONS.join(', ')}."
    end

    def has_embedding(*sources, column: :embedding, dimensions: nil, using: :neighbor, later: false)
      raise ArgumentError, "has_embedding requires at least one attribute" if sources.empty?
      raise ArgumentError, "has_embedding using: must be :neighbor or :ruby" unless BACKENDS.include?(using)
      raise ArgumentError, "has_embedding later: must be true, false or a Hash of job options" unless [ true, false ].include?(later) || later.is_a?(Hash)
      raise ArgumentError, "#{name} already uses has_chunks. A model uses has_embedding or has_chunks, not both." if respond_to?(:chunk_options)

      class_attribute :embedding_options, instance_writer: false
      self.embedding_options = {
        sources: sources.map(&:to_sym),
        column: column.to_sym,
        using: using,
        job_options: later.is_a?(Hash) ? Embeddable.validate_job_options!(later, "later:") : {}
      }

      if using == :neighbor
        unless respond_to?(:has_neighbors)
          raise OmniAgent::MissingDependencyError,
                "has_embedding needs the neighbor gem: add `gem \"neighbor\"` to your Gemfile. " \
                "Without a vector database, `using: :ruby` works for small tables only."
        end

        has_neighbors column, dimensions: dimensions
      end

      extend ClassMethods
      include InstanceMethods

      if later
        after_commit :embed_later, on: %i[create update], if: -> { embedding_sources.any? { |source| saved_change_to_attribute?(source) } }
      else
        before_save :assign_embedding, if: -> { embedding_sources.any? { |source| will_save_change_to_attribute?(source) } }
      end
    end

    module ClassMethods
      def semantic_search(query, limit: 5)
        vector = OmniAgent.embed(query)
        column = embedding_options[:column]

        if embedding_options[:using] == :ruby
          # ponytail: loads every embedded row and ranks in Ruby, O(n) per search; use neighbor past ~10k rows.
          all.where.not(column => nil).to_a.max_by(limit) { |record| cosine_similarity(record[column], vector) }
        else
          all.nearest_neighbors(column, vector, distance: "cosine").first(limit)
        end
      end

      # Embeds records that have no vector yet, or every record with
      # force: true (e.g. after switching embedding models).
      def embed_all(force: false, batch_size: 100)
        column = embedding_options[:column]
        records = force ? all : all.where(column => nil)

        records.find_in_batches(batch_size: batch_size) do |batch|
          batch = batch.reject { |record| record.embedding_text.blank? }
          next if batch.empty?

          OmniAgent.embed(batch.map(&:embedding_text)).zip(batch) do |vector, record|
            record.update_column(column, vector)
          end
        end
      end

      private

      def cosine_similarity(a, b)
        norms = Math.sqrt(a.sum { |x| x * x }) * Math.sqrt(b.sum { |x| x * x })
        norms.zero? ? 0.0 : a.zip(b).sum { |x, y| x * y } / norms
      end
    end

    module InstanceMethods
      # The text that gets embedded, and what a `searches` tool shows the model.
      def embedding_text
        embedding_sources.filter_map { |source| public_send(source).presence&.to_s }.join("\n\n")
      end

      def embed!
        update_column(embedding_options[:column], embedding_for(embedding_text))
      end

      private

      def embedding_sources
        embedding_options[:sources]
      end

      def embedding_for(text)
        text.blank? ? nil : OmniAgent.embed(text)
      end

      def assign_embedding
        self[embedding_options[:column]] = embedding_for(embedding_text)
      end

      def embed_later
        job_options = OmniAgent.configuration.embedding_job_options.merge(embedding_options[:job_options])
        OmniAgent::EmbedJob.set(**job_options).perform_later(self)
      end
    end
  end
end
