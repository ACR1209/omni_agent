require "rails/generators/named_base"

module OmniAgent
  module Generators
    class EmbeddingsGenerator < Rails::Generators::NamedBase
      BACKENDS = %w[pgvector sqlite mariadb ruby].freeze
      PGVECTOR_INDEX_MAX_DIMENSIONS = 2000

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
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        create_file File.join("db", "migrate", "#{timestamp}_#{migration_name.underscore}.rb"), migration_template
      end

      def create_sqlite_initializer
        return unless backend == "sqlite"
        return if File.exist?(File.join(destination_root, "config", "initializers", "neighbor.rb"))

        create_file File.join("config", "initializers", "neighbor.rb"), "# Load the sqlite-vec extension\nNeighbor::SQLite.initialize!\n"
      end

      def add_has_embedding
        model_path = File.join("app", "models", "#{file_path}.rb")
        raise Thor::Error, "#{model_path} not found. Generate the model first." unless File.exist?(File.join(destination_root, model_path))

        inject_into_class model_path, class_name, model_lines
      end

      def show_next_steps
        say ""
        if backend == "ruby"
          say "Warning: the Ruby backend loads every row on each search. Use it for small tables only " \
              "(under ~10k rows), and move to pgvector, sqlite-vec or MariaDB as the table grows.", :yellow
          say ""
        else
          say "Add the gems if you haven't:"
          say "  bundle add neighbor#{backend == 'sqlite' ? ' sqlite-vec' : ''}"
        end
        say "Then migrate and embed existing records:"
        say "  bin/rails db:migrate"
        say "  bin/rails \"omni_agent:embeddings:backfill[#{class_name}]\""
        say ""
        say "Give an agent a search tool with:"
        say "  searches #{class_name}"
      end

      private

      def backend
        @backend ||= options[:backend] || detect_backend
      end

      def detect_backend
        case ActiveRecord::Base.connection_db_config.adapter
        when /postg/ then "pgvector"
        when /sqlite/ then "sqlite"
        when /mysql|trilogy/
          return "mariadb" if mariadb?

          raise Thor::Error, "MySQL can't search vectors without HeatWave. Use Postgres, SQLite or MariaDB 11.8+, " \
                             "or pass --backend=ruby, which loads every row on each search and only suits small tables."
        else
          raise Thor::Error, "Couldn't detect a vector backend for this database. Pass --backend=#{BACKENDS.join('|')}."
        end
      end

      def mariadb?
        ActiveRecord::Base.with_connection(&:mariadb?)
      rescue ActiveRecord::ActiveRecordError => e
        raise Thor::Error, "Couldn't connect to the database to tell MySQL from MariaDB (#{e.message}). " \
                           "Create it first, or pass --backend=mariadb|ruby."
      end

      def dimensions
        return if backend == "ruby"

        @dimensions ||= options[:dimensions] || detect_dimensions
      end

      def detect_dimensions
        OmniAgent.embed("dimension check").length
      rescue StandardError => e
        raise Thor::Error, "Couldn't call the embedding model to detect its dimensions (#{e.message}). Pass --dimensions=N."
      end

      def column
        options[:column]
      end

      def migration_name
        "Add#{column.camelize}To#{table_name.camelize}"
      end

      def migration_template
        <<~RUBY
          class #{migration_name} < ActiveRecord::Migration[#{ActiveRecord::Migration.current_version}]
            def change
          #{migration_body.map { |line| line.empty? ? "" : "    #{line}" }.join("\n")}
            end
          end
        RUBY
      end

      def migration_body
        case backend
        when "pgvector"
          lines = [ 'enable_extension "vector"', "add_column :#{table_name}, :#{column}, :vector, limit: #{dimensions}" ]
          if dimensions <= PGVECTOR_INDEX_MAX_DIMENSIONS
            lines << "add_index :#{table_name}, :#{column}, using: :hnsw, opclass: :vector_cosine_ops"
          else
            lines << "# pgvector can't index more than #{PGVECTOR_INDEX_MAX_DIMENSIONS} dimensions; searches scan the table."
          end
        when "sqlite"
          [ "add_column :#{table_name}, :#{column}, :binary" ]
        when "mariadb"
          [
            "add_column :#{table_name}, :#{column}, :vector, limit: #{dimensions}",
            "# For a vector index, backfill first, then in a new migration:",
            "#   change_column_null :#{table_name}, :#{column}, false",
            "#   add_index :#{table_name}, :#{column}, type: :vector"
          ]
        when "ruby"
          [ "add_column :#{table_name}, :#{column}, :json" ]
        end
      end

      def model_lines
        arguments = sources.map { |source| ":#{source}" }
        arguments << "column: :#{column}" unless column == "embedding"
        arguments << "dimensions: #{dimensions}" if backend == "sqlite"
        arguments << "using: :ruby" if backend == "ruby"
        arguments << "later: true" if options[:later]

        lines = []
        lines << "  # Ruby backend, small tables only: every search loads and ranks all rows in Ruby.\n" if backend == "ruby"
        lines << "  has_embedding #{arguments.join(', ')}\n"
        lines.join
      end
    end
  end
end
