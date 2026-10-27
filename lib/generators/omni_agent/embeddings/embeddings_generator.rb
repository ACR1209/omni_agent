require "rails/generators/named_base"
require_relative "../vector_store"

module OmniAgent
  module Generators
    class EmbeddingsGenerator < Rails::Generators::NamedBase
      include VectorStore

      desc "Adds an embedding column to a model and declares has_embedding on it"

      argument :sources, type: :array, banner: "attribute [attribute ...]", desc: "Attributes to embed"

      class_option :column, type: :string, default: "embedding", desc: "Column that stores the vector"
      class_option :dimensions, type: :numeric, desc: "Vector size (default: detected by calling the embedding model once)"
      class_option :backend, type: :string, enum: BACKENDS, desc: "Default: detected from the database adapter"
      class_option :later, type: :boolean, default: false, desc: "Embed in a background job after commit"

      def check_backend_and_dimensions
        backend
        dimensions
      end

      def create_migration_file
        migration_file(migration_name, vector_column_lines(table_name, column))
      end

      def create_vector_store_initializer
        create_sqlite_initializer
      end

      def add_has_embedding
        model_path = File.join("app", "models", "#{file_path}.rb")
        raise Thor::Error, "#{model_path} not found. Generate the model first." unless File.exist?(File.join(destination_root, model_path))

        inject_into_class model_path, class_name, model_lines
      end

      def show_next_steps
        say ""
        say_vector_store_setup
        say "Then migrate and embed existing records:"
        say "  bin/rails db:migrate"
        say "  bin/rails \"omni_agent:embeddings:backfill[#{class_name}]\""
        say ""
        say "Give an agent a search tool with:"
        say "  searches #{class_name}"
      end

      private

      def column
        options[:column]
      end

      def migration_name
        "Add#{column.camelize}To#{table_name.camelize}"
      end

      def model_lines
        arguments = sources.map { |source| ":#{source}" }
        arguments << "column: :#{column}" unless column == "embedding"
        arguments.concat(vector_store_options)
        arguments << "later: true" if options[:later]

        lines = []
        lines << "  # Ruby backend, small tables only: every search loads and ranks all rows in Ruby.\n" if backend == "ruby"
        lines << "  has_embedding #{arguments.join(', ')}\n"
        lines.join
      end
    end
  end
end
