require_relative "../rails_helper"
require Gem.loaded_specs["activestorage"].full_gem_path + "/db/migrate/20170806125915_create_active_storage_tables"

RSpec.describe OmniAgent::Chunkable do
  include ActiveJob::TestHelper

  let(:fixtures) { File.expand_path("../fixtures/documents", __dir__) }

  before(:all) do
    connection = ActiveRecord::Base.connection
    ActiveRecord::Migration.suppress_messages { CreateActiveStorageTables.migrate(:up) } unless connection.table_exists?(:active_storage_blobs)

    connection.create_table(:chunked_documents, force: true) do |t|
      t.text :body
      t.integer :account_id
    end
    connection.create_table(:chunked_document_chunks, force: true) do |t|
      t.references :chunked_document
      t.integer :position
      t.text :content
      t.text :context
      t.json :metadata
      t.json :embedding
    end
  end

  after(:all) do
    connection = ActiveRecord::Base.connection
    %i[chunked_documents chunked_document_chunks active_storage_variant_records active_storage_attachments active_storage_blobs]
      .each { |table| connection.drop_table(table, if_exists: true) }
    FileUtils.rm_rf(ActiveStorage::Blob.service.root)
  end

  before do
    OmniAgent.instance_variable_set(:@configuration, nil)
    OmniAgent.configure { |config| config.embedding_provider = :mock }
    stub_const("ChunkedDocumentChunk", Class.new(ActiveRecord::Base) do
      belongs_to :chunked_document
      has_embedding :content, using: :ruby
    end)
  end

  after do
    OmniAgent.instance_variable_set(:@configuration, nil)
  end

  def document_class(source = :body, **options)
    stub_const("ChunkedDocument", Class.new(ActiveRecord::Base) do
      has_one_attached :file
      has_chunks source, class_name: "ChunkedDocumentChunk", size: 40, overlap: 0, later: false, **options
    end)
  end

  def upload(name, content_type: nil)
    { io: File.open(File.join(fixtures, name)), filename: name, content_type: content_type }.compact
  end

  def mock_vector(text)
    OmniAgent::Providers::Mock.new.embed([ text ]).first
  end

  describe "has_chunks" do
    it "chunks and embeds a text column on save" do
      document = document_class.create!(body: "Refunds take 30 days.\n\nShipping is free worldwide.")

      expect(document.chunks.map { |chunk| [ chunk.position, chunk.content ] })
        .to eq([ [ 0, "Refunds take 30 days." ], [ 1, "Shipping is free worldwide." ] ])
      expect(document.chunks.first.embedding).to eq(mock_vector("Refunds take 30 days."))
    end

    it "embeds all chunks of a document in one call" do
      expect(OmniAgent).to receive(:embed).once.and_call_original

      document_class.create!(body: "Refunds take 30 days.\n\nShipping is free worldwide.")
    end

    it "replaces the chunks when the source changes, re-embedding only new text" do
      document = document_class.create!(body: "Refunds take 30 days.\n\nShipping is free worldwide.")
      expect(OmniAgent).to receive(:embed).with([ "Shipping costs $5." ]).and_call_original

      document.update!(body: "Refunds take 30 days.\n\nShipping costs $5.")

      expect(document.chunks.pluck(:content)).to eq([ "Refunds take 30 days.", "Shipping costs $5." ])
    end

    it "leaves the chunks alone when other attributes change" do
      document = document_class.create!(body: "Refunds take 30 days.")
      expect(OmniAgent).not_to receive(:embed)

      document.update!(account_id: 2)
    end

    it "removes the chunks when the source is cleared" do
      document = document_class.create!(body: "Refunds take 30 days.")
      document.update!(body: "")

      expect(document.chunks).to be_empty
    end

    it "stores the chunker's context and metadata" do
      document = document_class(chunker: :hierarchical).create!(body: "# Refunds\n\nRefunds take 30 days.\n\nAsk support for help.")

      expect(document.chunks.map(&:content)).to eq([ "# Refunds\n\nRefunds take 30 days.", "Ask support for help." ])
      expect(document.chunks.map(&:context).uniq).to eq([ "# Refunds\n\nRefunds take 30 days.\n\nAsk support for help." ])
      expect(document.chunks.first.metadata).to eq("headings" => [ "Refunds" ])
    end

    it "deletes the chunks with the document" do
      document = document_class.create!(body: "Refunds take 30 days.")

      expect { document.destroy! }.to change(ChunkedDocumentChunk, :count).by(-1)
    end

    it "rejects invalid options" do
      expect { document_class(size: 10, overlap: 10) }.to raise_error(ArgumentError, /overlap: must be between 0 and size:/)
      expect { document_class(chunker: :semantic) }.to raise_error(ArgumentError, /Unknown chunker/)
      expect { document_class(as: :docx) }.to raise_error(ArgumentError, /Unknown loader/)
    end

    it "can't be combined with has_embedding" do
      embedded_first = proc do
        has_embedding :body, using: :ruby
        has_chunks :body
      end
      chunked_first = proc do
        has_chunks :body
        has_embedding :body, using: :ruby
      end

      expect { Class.new(ActiveRecord::Base, &embedded_first) }.to raise_error(ArgumentError, /has_embedding or has_chunks, not both/)
      expect { Class.new(ActiveRecord::Base, &chunked_first) }.to raise_error(ArgumentError, /has_embedding or has_chunks, not both/)
    end

    it "explains a chunk model without has_embedding" do
      stub_const("ChunkedDocumentChunk", Class.new(ActiveRecord::Base))

      expect { document_class.create!(body: "Refunds") }
        .to raise_error(OmniAgent::Error, /ChunkedDocumentChunk needs `has_embedding :content`/)
    end
  end

  describe "with an attachment" do
    it "auto-detects the file's format" do
      document = document_class(:file).create!(file: upload("refunds.pdf"))

      expect(document.chunks.pluck(:content)).to eq([ "Refunds take 30 days." ])
    end

    it "re-ingests when a new file is attached" do
      document = document_class(:file).create!(file: upload("refunds.pdf"))
      document.file.attach(io: StringIO.new("Shipping is free."), filename: "shipping.txt")

      expect(document.chunks.pluck(:content)).to eq([ "Shipping is free." ])
    end

    it "reads the upload even when has_chunks is declared before has_one_attached" do
      stub_const("ChunkedDocument", Class.new(ActiveRecord::Base) do
        has_chunks :file, class_name: "ChunkedDocumentChunk", later: false
        has_one_attached :file
      end)

      document = ChunkedDocument.create!(file: upload("refunds.pdf"))

      expect(document.chunks.pluck(:content)).to eq([ "Refunds take 30 days." ])
    end

    it "rejects other formats at save when the loader is enforced" do
      document = document_class(:file, as: :pdf).new(file: { io: StringIO.new("plain"), filename: "notes.txt" })

      expect(document).not_to be_valid
      expect(document.errors[:file]).to eq([ "must be a PDF file" ])
    end

    it "skips files no loader can read without failing the save" do
      document = document_class(:file).create!(file: { io: StringIO.new("PK\x03\x04\0\0"), filename: "archive.zip" })

      expect(document).to be_persisted
      expect(document.chunks).to be_empty
    end
  end

  describe "in a background job" do
    it "ingests after commit with later: true, using the embedding job options" do
      OmniAgent.configure { |config| config.embedding_job_options = { queue: :embeddings } }
      document = document_class(later: true).create!(body: "Refunds take 30 days.")

      expect(document.chunks).to be_empty
      expect(enqueued_jobs.last).to include("job_class" => "OmniAgent::IngestJob", "queue_name" => "embeddings")

      perform_enqueued_jobs
      expect(document.chunks.reload.pluck(:content)).to eq([ "Refunds take 30 days." ])
    end

    it "lets the model override the job options" do
      document_class(later: { queue: :critical }).create!(body: "Refunds")

      expect(enqueued_jobs.last).to include("queue_name" => "critical")
    end

    it "discards jobs for deleted documents and unreadable files" do
      document_class(:file, later: true).create!(file: { io: StringIO.new("PK\x03\x04\0\0"), filename: "archive.zip" })
      document_class(later: true).create!(body: "Refunds").destroy!

      expect { perform_enqueued_jobs }.not_to raise_error
    end
  end

  describe ".semantic_search" do
    it "returns the closest chunks of the documents in scope" do
      documents = document_class
      own = documents.create!(body: "refunds", account_id: 1)
      documents.create!(body: "refunds", account_id: 2)

      expect(documents.where(account_id: 1).semantic_search("refunds")).to eq(own.chunks.to_a)
    end

    it "counts children of the same parent section once" do
      documents = document_class(chunker: :hierarchical, size: 20)
      document = documents.create!(body: "Refunds take 30 days.\n\nAsk support for help.")

      results = documents.semantic_search("refunds", limit: 5)

      expect(document.chunks.count).to be > 1
      expect(results.length).to eq(1)
    end
  end

  describe "Agent.searches" do
    def search(agent, query, context: {})
      tool = agent.tool_classes.last.new
      tool.context = context
      tool.invoke("query" => query)
    end

    let(:agent) do
      Class.new(OmniAgent::Agent) do
        def self.name
          "ChunkSearchAgent"
        end

        searches ChunkedDocument, scope: ->(context) { where(account_id: context[:account_id]) }
      end
    end

    it "searches the chunks of the documents in scope, tagged with their document and headings" do
      document_class(chunker: :markdown)
      own = ChunkedDocument.create!(body: "# Billing\n\n## Refunds\n\nRefunds take 30 days.", account_id: 1)
      ChunkedDocument.create!(body: "Refunds take 30 days.", account_id: 2)

      expect(agent.tool_classes.last.name).to end_with("SearchChunkedDocuments")
      expect(search(agent, "Refunds", context: { account_id: 1 })).to eq(
        "[ChunkedDocument##{own.id} › Billing › Refunds] ## Refunds\n\nRefunds take 30 days."
      )
    end
  end

  describe ".ingest_all" do
    it "ingests documents without chunks, or every document with force: true" do
      documents = document_class
      missing = documents.create!(body: "Refunds")
      missing.chunks.delete_all
      kept = documents.create!(body: "Shipping")
      kept.chunks.update_all(content: "stale")

      documents.ingest_all
      expect(missing.chunks.reload.pluck(:content)).to eq([ "Refunds" ])
      expect(kept.chunks.pluck(:content)).to eq([ "stale" ])

      documents.ingest_all(force: true)
      expect(kept.chunks.pluck(:content)).to eq([ "Shipping" ])
    end
  end
end
