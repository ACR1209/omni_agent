require_relative "../../rails_helper"
require "rails/generators"
require "generators/omni_agent/embeddings/embeddings_generator"

RSpec.describe OmniAgent::Generators::EmbeddingsGenerator do
  around do |example|
    Dir.mktmpdir do |dir|
      @destination = dir
      FileUtils.mkdir_p(File.join(dir, "app", "models"))
      File.write(File.join(dir, "app", "models", "document.rb"), "class Document < ApplicationRecord\nend\n")
      example.run
    end
  end

  before do
    OmniAgent.instance_variable_set(:@configuration, nil)
    OmniAgent.configure { |config| config.embedding_provider = :mock }
  end

  after do
    OmniAgent.instance_variable_set(:@configuration, nil)
  end

  def generate(*args)
    capture = StringIO.new
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = capture
    $stderr = capture
    described_class.start([ "Document", "title", "content", *args ], destination_root: @destination)
    capture.string
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end

  def migration
    path = Dir[File.join(@destination, "db", "migrate", "*_add_embedding_to_documents.rb")].first
    path && File.read(path)
  end

  def model
    File.read(File.join(@destination, "app", "models", "document.rb"))
  end

  it "writes a pgvector migration with a cosine HNSW index" do
    generate("--backend=pgvector", "--dimensions=1536")

    expect(migration).to include('enable_extension "vector"')
    expect(migration).to include("add_column :documents, :embedding, :vector, limit: 1536")
    expect(migration).to include("add_index :documents, :embedding, using: :hnsw, opclass: :vector_cosine_ops")
    expect(model).to include("  has_embedding :title, :content\n")
  end

  it "skips the pgvector index above 2,000 dimensions" do
    generate("--backend=pgvector", "--dimensions=3072")

    expect(migration).to include("limit: 3072")
    expect(migration).not_to include("add_index")
  end

  it "writes a binary column, the sqlite-vec initializer and model dimensions for SQLite" do
    generate("--backend=sqlite", "--dimensions=768")

    expect(migration).to include("add_column :documents, :embedding, :binary")
    expect(File.read(File.join(@destination, "config", "initializers", "neighbor.rb"))).to include("Neighbor::SQLite.initialize!")
    expect(model).to include("has_embedding :title, :content, dimensions: 768")
  end

  it "writes a vector column for MariaDB" do
    generate("--backend=mariadb", "--dimensions=768")

    expect(migration).to include("add_column :documents, :embedding, :vector, limit: 768")
  end

  it "writes a JSON column and a warning for the Ruby fallback" do
    output = generate("--backend=ruby", "--later", "--column=vector")

    expect(Dir[File.join(@destination, "db", "migrate", "*_add_vector_to_documents.rb")].map { |path| File.read(path) })
      .to contain_exactly(include("add_column :documents, :vector, :json"))
    expect(model).to include("has_embedding :title, :content, column: :vector, using: :ruby, later: true")
    expect(model).to include("small tables only")
    expect(output).to match(/every row/i)
  end

  it "detects the database adapter and the model's dimensions" do
    generate

    expect(migration).to include("add_column :documents, :embedding, :binary")
    expect(model).to include("dimensions: 8")
  end

  it "refuses plain MySQL unless the Ruby fallback is requested" do
    allow(ActiveRecord::Base).to receive(:connection_db_config).and_return(double(adapter: "mysql2"))
    allow(ActiveRecord::Base).to receive(:with_connection).and_yield(double(mariadb?: false))

    output = generate

    expect(output).to match(/HeatWave/)
    expect(migration).to be_nil
  end

  it "asks for --dimensions when the embedding model can't be reached" do
    allow(OmniAgent).to receive(:embed).and_raise(OmniAgent::Error, "no API key")

    output = generate("--backend=pgvector")

    expect(output).to match(/--dimensions/)
    expect(migration).to be_nil
  end
end
