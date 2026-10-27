require_relative "../rails_helper"

RSpec.describe OmniAgent::Embeddable do
  include ActiveJob::TestHelper

  before(:all) do
    ActiveRecord::Base.connection.create_table(:embeddable_notes, force: true) do |t|
      t.string :title
      t.text :body
      t.integer :account_id
      t.json :embedding
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.drop_table(:embeddable_notes, if_exists: true)
  end

  before do
    OmniAgent.instance_variable_set(:@configuration, nil)
    OmniAgent.configure { |config| config.embedding_provider = :mock }
  end

  after do
    OmniAgent.instance_variable_set(:@configuration, nil)
  end

  def note_class(**options)
    Class.new(ActiveRecord::Base) do
      self.table_name = "embeddable_notes"
      def self.name
        "Note"
      end

      has_embedding :title, :body, using: :ruby, **options
    end
  end

  def mock_vector(text)
    OmniAgent::Providers::Mock.new.embed([ text ]).first
  end

  describe "has_embedding" do
    it "embeds the joined source attributes on save" do
      note = note_class.create!(title: "Refunds", body: "Within 30 days")

      expect(note.embedding_text).to eq("Refunds\n\nWithin 30 days")
      expect(note.reload.embedding).to eq(mock_vector("Refunds\n\nWithin 30 days"))
    end

    it "only re-embeds when a source attribute changes" do
      note = note_class.create!(title: "Refunds", body: "Within 30 days")
      expect(OmniAgent).not_to receive(:embed)

      note.update!(account_id: 7)
    end

    it "re-embeds when a source attribute changes" do
      note = note_class.create!(title: "Refunds", body: "Within 30 days")

      note.update!(body: "Within 60 days")

      expect(note.reload.embedding).to eq(mock_vector("Refunds\n\nWithin 60 days"))
    end

    it "stores nil without calling the provider when every source is blank" do
      expect(OmniAgent).not_to receive(:embed)

      expect(note_class.create!(title: "", body: nil).embedding).to be_nil
    end

    it "embeds in a background job after commit with later: true" do
      note = note_class(later: true).create!(title: "Refunds", body: "Within 30 days")
      expect(note.reload.embedding).to be_nil

      expect(enqueued_jobs.map { |job| job["job_class"] }).to eq([ "OmniAgent::EmbedJob" ])
      note.embed!
      expect(note.reload.embedding).to eq(mock_vector("Refunds\n\nWithin 30 days"))
    end

    it "discards the job when the record is deleted before it runs" do
      note = note_class(later: true).create!(title: "Refunds")
      note.destroy!

      expect { perform_enqueued_jobs }.not_to raise_error
    end

    it "explains how to enable ActiveJob when later: true is used without it" do
      hide_const("ActiveJob")

      expect {
        Class.new(ActiveRecord::Base) { has_embedding :body, using: :ruby, later: true }
      }.to raise_error(OmniAgent::MissingDependencyError, %r{active_job/railtie})
    end

    it "requires at least one source attribute" do
      expect {
        Class.new(ActiveRecord::Base) { has_embedding }
      }.to raise_error(ArgumentError, /at least one attribute/)
    end

    it "rejects an unknown backend" do
      expect {
        Class.new(ActiveRecord::Base) { has_embedding :body, using: :faiss }
      }.to raise_error(ArgumentError, /using: must be :neighbor or :ruby/)
    end
  end

  describe ".semantic_search with using: :ruby" do
    it "returns the closest records first, respecting the current scope" do
      notes = note_class
      match = notes.create!(title: "refunds", account_id: 1)
      notes.create!(title: "shipping", account_id: 1)
      notes.create!(title: "refunds", account_id: 2)
      notes.create!(title: "", account_id: 1)

      results = notes.where(account_id: 1).semantic_search("refunds", limit: 2)

      expect(results.length).to eq(2)
      expect(results.first).to eq(match)
      expect(results.map(&:account_id).uniq).to eq([ 1 ])
    end
  end

  describe ".semantic_search with neighbor" do
    it "declares the column with has_neighbors and searches it by cosine distance" do
      notes = Class.new(ActiveRecord::Base) do
        self.table_name = "embeddable_notes"
        def self.name
          "Note"
        end

        has_embedding :body, dimensions: 8
      end

      expect(notes.neighbor_attributes[:embedding]).to include(dimensions: 8)

      relation = double("relation")
      allow(notes).to receive(:all).and_return(relation)
      expect(relation).to receive(:nearest_neighbors)
        .with(:embedding, mock_vector("refunds"), distance: "cosine")
        .and_return(double("ranked", first: [ :hit ]))

      expect(notes.semantic_search("refunds", limit: 3)).to eq([ :hit ])
    end
  end

  describe ".embed_all" do
    it "embeds records missing a vector, or every record with force: true" do
      notes = note_class
      first = notes.create!(title: "one")
      second = notes.create!(title: "two")
      first.update_column(:embedding, nil)
      second.update_column(:embedding, [ 0.0 ])

      notes.embed_all
      expect(first.reload.embedding).to eq(mock_vector("one"))
      expect(second.reload.embedding).to eq([ 0.0 ])

      notes.embed_all(force: true)
      expect(second.reload.embedding).to eq(mock_vector("two"))
    end
  end
end
