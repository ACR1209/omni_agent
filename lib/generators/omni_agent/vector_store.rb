module OmniAgent
  module Generators
    # Picks the vector store and vector size for the embeddings and chunks
    # generators, and writes what each store needs. Expects `backend` and
    # `dimensions` class options.
    module VectorStore
      BACKENDS = %w[pgvector sqlite mariadb ruby].freeze
      PGVECTOR_INDEX_MAX_DIMENSIONS = 2000

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

      # Migration lines that add a vector column (and its index) to a table.
      def vector_column_lines(table, column)
        case backend
        when "pgvector"
          lines = [ 'enable_extension "vector"', "add_column :#{table}, :#{column}, :vector, limit: #{dimensions}" ]
          if dimensions <= PGVECTOR_INDEX_MAX_DIMENSIONS
            lines << "add_index :#{table}, :#{column}, using: :hnsw, opclass: :vector_cosine_ops"
          else
            lines << "# pgvector can't index more than #{PGVECTOR_INDEX_MAX_DIMENSIONS} dimensions; searches scan the table."
          end
        when "sqlite"
          [ "add_column :#{table}, :#{column}, :binary" ]
        when "mariadb"
          [
            "add_column :#{table}, :#{column}, :vector, limit: #{dimensions}",
            "# For a vector index, backfill first, then in a new migration:",
            "#   change_column_null :#{table}, :#{column}, false",
            "#   add_index :#{table}, :#{column}, type: :vector"
          ]
        when "ruby"
          [ "add_column :#{table}, :#{column}, :json" ]
        end
      end

      def migration_file(name, body_lines)
        # Like Rails' generators: after the newest migration, even one created this same second.
        newest = Dir[File.join(destination_root, "db", "migrate", "*.rb")].map { |path| File.basename(path).to_i }.max.to_i
        number = [ Time.now.utc.strftime("%Y%m%d%H%M%S").to_i, newest + 1 ].max
        create_file File.join("db", "migrate", "#{number}_#{name.underscore}.rb"), <<~RUBY
          class #{name} < ActiveRecord::Migration[#{ActiveRecord::Migration.current_version}]
            def change
          #{body_lines.map { |line| line.empty? ? "" : "    #{line}" }.join("\n")}
            end
          end
        RUBY
      end

      def create_sqlite_initializer
        return unless backend == "sqlite"
        return if File.exist?(File.join(destination_root, "config", "initializers", "neighbor.rb"))

        create_file File.join("config", "initializers", "neighbor.rb"), "# Load the sqlite-vec extension\nNeighbor::SQLite.initialize!\n"
      end

      # has_embedding arguments the store needs.
      def vector_store_options
        if backend == "sqlite" then [ "dimensions: #{dimensions}" ]
        elsif backend == "ruby" then [ "using: :ruby" ]
        else []
        end
      end

      def say_vector_store_setup
        if backend == "ruby"
          say "Warning: the Ruby backend loads every row on each search. Use it for small tables only " \
              "(under ~10k rows), and move to pgvector, sqlite-vec or MariaDB as the table grows.", :yellow
          say ""
        else
          say "Add the gems if you haven't:"
          say "  bundle add neighbor#{backend == 'sqlite' ? ' sqlite-vec' : ''}"
        end
      end
    end
  end
end
