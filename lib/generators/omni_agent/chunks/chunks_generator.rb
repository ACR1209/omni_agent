require "rails/generators/named_base"
require_relative "../vector_store"

module OmniAgent
  module Generators
    class ChunksGenerator < Rails::Generators::NamedBase
      include VectorStore

      desc "Creates a chunk model for a document model and declares has_chunks on it"

      argument :source, type: :string, banner: "source", desc: "Attachment, text column or rich text to chunk"

      class_option :as, type: :string, desc: "Loader to enforce (pdf, html, markdown, text). Default: detected per file"
      class_option :chunker, type: :string, enum: OmniAgent::Chunkers.registry.keys.map(&:to_s), desc: "Default: recursive"
      class_option :size, type: :numeric, desc: "Chunk size in characters. Default: 1000"
      class_option :overlap, type: :numeric, desc: "Characters repeated between chunks. Default: 200"
      class_option :inline, type: :boolean, default: false, desc: "Ingest during save instead of in a background job"
      class_option :dimensions, type: :numeric, desc: "Vector size (default: detected by calling the embedding model once)"
      class_option :backend, type: :string, enum: BACKENDS, desc: "Default: detected from the database adapter"

      def check_backend_and_dimensions
        raise Thor::Error, "#{model_path} not found. Generate the model first." unless File.exist?(File.join(destination_root, model_path))

        backend
        dimensions
      end

      def create_migration_file
        migration_file("Create#{chunk_table.camelize}", [
          "create_table :#{chunk_table} do |t|",
          "  t.references :#{reference}, null: false, foreign_key: { to_table: :#{table_name} }",
          "  t.integer :position, null: false",
          "  t.text :content, null: false",
          "  t.text :context",
          "  t.json :metadata",
          "end",
          "add_index :#{chunk_table}, [ :#{reference}_id, :position ]",
          *vector_column_lines(chunk_table, "embedding")
        ])
      end

      def create_vector_store_initializer
        create_sqlite_initializer
      end

      def create_chunk_model
        lines = [ "class #{chunk_class} < ApplicationRecord" ]
        lines << "  belongs_to :#{reference}#{", class_name: \"#{class_name}\"" if reference.camelize != class_name}"
        lines << "  # Ruby backend, small tables only: every search loads and ranks all rows in Ruby." if backend == "ruby"
        lines << "  has_embedding #{[ ':content', *vector_store_options ].join(', ')}"
        lines << "end"
        create_file File.join("app", "models", "#{file_path}_chunk.rb"), lines.join("\n") + "\n"
      end

      def add_has_chunks
        lines = []
        lines << "  has_one_attached :#{source}\n" if attachment_needed?
        lines << "  has_chunks #{chunk_arguments.join(', ')}\n"
        inject_into_class model_path, class_name, lines.join
      end

      def show_next_steps
        say ""
        say_vector_store_setup
        say "To read PDFs, also:"
        say "  bundle add pdf-reader"
        say "Then migrate and ingest existing records:"
        say "  bin/rails active_storage:install # if #{source} is an upload and you haven't" if attachment?
        say "  bin/rails db:migrate"
        say "  bin/rails \"omni_agent:chunks:ingest[#{class_name}]\""
        say ""
        say "Give an agent a search tool with:"
        say "  searches #{class_name}"
      end

      private

      def model_path
        File.join("app", "models", "#{file_path}.rb")
      end

      def chunk_class
        "#{class_name}Chunk"
      end

      def chunk_table
        "#{singular_table_name}_chunks"
      end

      def reference
        class_name.demodulize.underscore
      end

      def chunk_arguments
        arguments = [ ":#{source}" ]
        arguments << "as: :#{options[:as]}" if options[:as]
        arguments << "chunker: :#{options[:chunker]}" if options[:chunker]
        arguments << "size: #{options[:size]}" if options[:size]
        arguments << "overlap: #{options[:overlap]}" if options[:overlap]
        arguments << "later: false" if options[:inline]
        arguments
      end

      def attachment?
        attachment_needed? || model_source.match?(/has_(one|many)_attached\s+:#{source}\b/)
      end

      # A source the model doesn't declare and the table doesn't have is an upload.
      def attachment_needed?
        return @attachment_needed if defined?(@attachment_needed)

        @attachment_needed = !model_source.match?(/(has_\w+|def|attribute|alias_attribute)\s+:?#{source}\b/) && !source_column?
      end

      def model_source
        File.read(File.join(destination_root, model_path))
      end

      # In the database, or in a migration that may not have run yet.
      def source_column?
        migrations = Dir[File.join(destination_root, "db", "migrate", "*.rb")].map { |path| File.read(path) }
        return true if migrations.any? { |migration| migration.include?(":#{table_name}") && migration.match?(/[:"]#{source}\b/) }

        ActiveRecord::Base.with_connection { |connection| connection.table_exists?(table_name) && connection.column_exists?(table_name, source) }
      rescue ActiveRecord::ActiveRecordError
        false
      end
    end
  end
end
