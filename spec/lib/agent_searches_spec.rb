require_relative "../rails_helper"

RSpec.describe "OmniAgent::Agent.searches" do
  before(:all) do
    ActiveRecord::Base.connection.create_table(:searchable_notes, force: true) do |t|
      t.text :body
      t.integer :account_id
      t.json :embedding
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.drop_table(:searchable_notes, if_exists: true)
  end

  before do
    OmniAgent.instance_variable_set(:@configuration, nil)
    OmniAgent.configure { |config| config.embedding_provider = :mock }
    stub_const("SearchableNote", Class.new(ActiveRecord::Base) do
      self.table_name = "searchable_notes"
      has_embedding :body, using: :ruby
    end)
  end

  after do
    OmniAgent.instance_variable_set(:@configuration, nil)
  end

  def agent_class(&block)
    Class.new(OmniAgent::Agent) do
      def self.name
        "SearchSpecAgent"
      end

      class_eval(&block)
    end
  end

  def run_tool(agent, query, context: {})
    tool = agent.tool_classes.find { |tool_class| tool_class.name.end_with?("SearchSearchableNotes") }
    instance = tool.new
    instance.context = context
    instance.invoke("query" => query)
  end

  it "adds a read-only Search<Models> tool that takes a query" do
    agent = agent_class { searches SearchableNote }
    tool = agent.tool_classes.last

    expect(tool.name.split("::").last).to eq("SearchSearchableNotes")
    expect(tool.json_schema[:properties].keys).to eq([ :query ])
    expect(tool.mcp_annotations).to include(readOnlyHint: true)
    expect(tool.description).to match(/searchable notes/i)
  end

  it "returns the matching records with their ids, closest first" do
    match = SearchableNote.create!(body: "refunds")
    SearchableNote.create!(body: "shipping")

    result = run_tool(agent_class { searches SearchableNote, limit: 1 }, "refunds")

    expect(result).to eq("[SearchableNote##{match.id}] refunds")
  end

  it "applies the scope with the run context, so other tenants never match" do
    own = SearchableNote.create!(body: "refunds", account_id: 1)
    SearchableNote.create!(body: "refunds", account_id: 2)
    agent = agent_class { searches SearchableNote, scope: ->(context) { where(account_id: context[:account_id]) } }

    result = run_tool(agent, "refunds", context: { account_id: 1 })

    expect(result).to eq("[SearchableNote##{own.id}] refunds")
  end

  it "says so when nothing matches" do
    expect(run_tool(agent_class { searches SearchableNote }, "refunds")).to eq("No results.")
  end

  it "accepts as: and description: overrides" do
    agent = agent_class { searches SearchableNote, as: :lookup_policies, description: "Find policies" }
    tool = agent.tool_classes.last

    expect(tool.name.split("::").last).to eq("LookupPolicies")
    expect(tool.description).to eq("Find policies")
  end

  it "searches any object that responds to semantic_search(query, limit:)" do
    store = Class.new do
      def self.name
        "Wiki"
      end

      def self.semantic_search(query, limit:)
        [ "#{query} page" ] * limit
      end
    end
    agent = agent_class { searches store, limit: 2 }
    tool = agent.tool_classes.last

    expect(tool.name.split("::").last).to eq("SearchWikis")
    expect(tool.new.invoke("query" => "refunds")).to eq("refunds page\n\nrefunds page")
  end

  it "rejects targets it can't search" do
    expect { agent_class { searches Class.new } }
      .to raise_error(ArgumentError, /can't be searched/)
  end

  describe "with a meilisearch-rails model" do
    before do
      stub_const("MeiliNote", Class.new(ActiveRecord::Base) do
        self.table_name = "searchable_notes"
        include Meilisearch::Rails
      end)
    end

    it "runs a hybrid search, pushing equality scopes down as filters" do
      kept = MeiliNote.create!(body: "refunds", account_id: 1)
      agent = agent_class { searches MeiliNote, scope: ->(context) { where(account_id: context[:account_id]) }, embedder: "openai" }

      expect(MeiliNote).to receive(:ms_search)
        .with("refunds", { limit: 5, hybrid: { embedder: "openai" }, filter: [ "account_id = 1" ] })
        .and_return([ kept ])

      tool = agent.tool_classes.last
      instance = tool.new
      instance.context = { account_id: 1 }

      expect(instance.invoke("query" => "refunds")).to eq("[MeiliNote##{kept.id}] body: refunds")
    end

    it "drops hits outside the scope even if the index returns them" do
      kept = MeiliNote.create!(body: "refunds", account_id: 1)
      leaked = MeiliNote.create!(body: "refunds", account_id: 2)
      allow(MeiliNote).to receive(:ms_search).and_return([ leaked, kept ])

      results = OmniAgent::SemanticSearch.call(MeiliNote.where(account_id: 1), "refunds", limit: 5)

      expect(results).to eq([ kept ])
    end
  end
end
