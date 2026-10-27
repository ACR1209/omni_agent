require_relative "../../rails_helper"
require "rails/generators"
require "generators/omni_agent/chunks/chunks_generator"

RSpec.describe OmniAgent::Generators::ChunksGenerator do
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
    described_class.start([ "Document", *args ], destination_root: @destination)
    capture.string
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end

  def read(path)
    full_path = File.join(@destination, path)
    File.read(full_path) if File.exist?(full_path)
  end

  def migration
    path = Dir[File.join(@destination, "db", "migrate", "*_create_document_chunks.rb")].first
    path && File.read(path)
  end

  it "creates the chunk table with a pgvector column and index" do
    generate("file", "--backend=pgvector", "--dimensions=1536")

    expect(migration).to include(
      "create_table :document_chunks do |t|",
      "t.references :document, null: false, foreign_key: { to_table: :documents }",
      "t.text :content, null: false",
      "t.text :context",
      "t.json :metadata",
      "add_index :document_chunks, [ :document_id, :position ]",
      "add_column :document_chunks, :embedding, :vector, limit: 1536",
      "add_index :document_chunks, :embedding, using: :hnsw, opclass: :vector_cosine_ops"
    )
  end

  it "creates the chunk model" do
    generate("file", "--backend=pgvector", "--dimensions=1536")

    expect(read("app/models/document_chunk.rb")).to eq(<<~RUBY)
      class DocumentChunk < ApplicationRecord
        belongs_to :document
        has_embedding :content
      end
    RUBY
  end

  it "declares an attachment for a source the model doesn't have" do
    output = generate("file", "--backend=pgvector", "--dimensions=1536")

    expect(read("app/models/document.rb")).to include("  has_one_attached :file\n  has_chunks :file\n")
    expect(output).to include("active_storage:install", "pdf-reader", "omni_agent:chunks:ingest[Document]")
  end

  it "uses an attachment or attribute the model already declares" do
    File.write(File.join(@destination, "app", "models", "document.rb"), "class Document < ApplicationRecord\n  has_rich_text :body\nend\n")

    generate("body", "--backend=pgvector", "--dimensions=1536")

    expect(read("app/models/document.rb")).not_to include("has_one_attached")
    expect(read("app/models/document.rb")).to include("has_chunks :body")
  end

  it "uses a column the table already has" do
    allow(ActiveRecord::Base).to receive(:with_connection).and_yield(double(table_exists?: true, column_exists?: true))

    generate("body", "--backend=pgvector", "--dimensions=1536")

    expect(read("app/models/document.rb")).not_to include("has_one_attached")
  end

  it "uses a column from a migration that hasn't run yet" do
    FileUtils.mkdir_p(File.join(@destination, "db", "migrate"))
    File.write(File.join(@destination, "db", "migrate", "20260101000000_create_documents.rb"), "create_table :documents do |t|\n  t.text :body\nend\n")

    generate("body", "--backend=pgvector", "--dimensions=1536")

    expect(read("app/models/document.rb")).not_to include("has_one_attached")
  end

  it "passes the loader, chunker and size options to has_chunks" do
    generate("file", "--as=pdf", "--chunker=hierarchical", "--size=500", "--overlap=50", "--inline", "--backend=pgvector", "--dimensions=8")

    expect(read("app/models/document.rb")).to include("has_chunks :file, as: :pdf, chunker: :hierarchical, size: 500, overlap: 50, later: false")
  end

  it "writes what SQLite and the Ruby fallback need" do
    generate("file", "--backend=sqlite", "--dimensions=768")
    expect(read("app/models/document_chunk.rb")).to include("has_embedding :content, dimensions: 768")
    expect(read("config/initializers/neighbor.rb")).to include("Neighbor::SQLite.initialize!")
  end

  it "warns about the Ruby fallback" do
    output = generate("file", "--backend=ruby")

    expect(migration).to include("add_column :document_chunks, :embedding, :json")
    expect(read("app/models/document_chunk.rb")).to include("small tables only", "has_embedding :content, using: :ruby")
    expect(output).to match(/every row/i)
  end

  it "asks for the document model first" do
    File.delete(File.join(@destination, "app", "models", "document.rb"))

    expect(generate("file", "--backend=ruby")).to match(%r{app/models/document.rb not found})
    expect(migration).to be_nil
  end
end
