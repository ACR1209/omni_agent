require_relative "../../spec_helper"
require_relative "../../../lib/omni_agent/tool/schema_builder"
require_relative "../../../lib/omni_agent/tool"

RSpec.describe OmniAgent::Tool do
  describe ".description" do
    it "returns the default when nothing has been set" do
      klass = Class.new(described_class)

      expect(klass.description).to eq("No description provided.")
    end

    it "stores and returns a custom description" do
      klass = Class.new(described_class)

      klass.description("Searches documents")

      expect(klass.description).to eq("Searches documents")
    end
  end

  describe ".metadata" do
    it "returns an empty hash by default" do
      klass = Class.new(described_class)

      expect(klass.metadata).to eq({})
    end

    it "stores and returns metadata" do
      klass = Class.new(described_class)

      klass.metadata(timeout: 5, retries: 2)

      expect(klass.metadata).to eq(timeout: 5, retries: 2)
    end
  end

  describe ".tags" do
    it "returns an empty array by default" do
      klass = Class.new(described_class)

      expect(klass.tags).to eq([])
    end

    it "stores normalized tags as symbols and de-duplicates" do
      klass = Class.new(described_class)

      klass.tags(:math, "person", :math)

      expect(klass.tags).to eq([:math, :person])
    end

    it "returns current tags when called with no arguments" do
      klass = Class.new(described_class)
      klass.tags(:math)

      expect(klass.tags).to eq([:math])
    end

    it "rejects non string and non symbol tags" do
      klass = Class.new(described_class)

      expect { klass.tags(:math, 123) }.to raise_error(ArgumentError, /tags must be strings or symbols/)
    end
  end

  describe ".input and .json_schema" do
    it "returns an empty schema when no input block has been defined" do
      klass = Class.new(described_class)

      expect(klass.json_schema).to eq(
        type: "object",
        properties: {},
        required: [],
        additionalProperties: false
      )
    end

    it "builds schema properties and required fields from the input DSL" do
      klass = Class.new(described_class)

      klass.input do
        string :query
        integer :limit, required: false
        hash :filters do
          boolean :archived, required: false
        end
      end

      expect(klass.json_schema).to eq(
        type: "object",
        properties: {
          query: { type: "string" },
          limit: { type: "integer" },
          filters: {
            type: "object",
            properties: {
              archived: { type: "boolean" }
            },
            required: [],
            additionalProperties: false
          }
        },
        required: ["query", "filters"],
        additionalProperties: false
      )
    end
  end

  describe ".invoke" do
    it "passes symbolized keyword arguments to #execute" do
      klass = Class.new(described_class) do
        attr_reader :received

        def execute(**args)
          @received = args
        end
      end

      tool_instance = klass.new
      allow(klass).to receive(:new).and_return(tool_instance)

      result = klass.invoke("term" => "ruby", "limit" => 3)

      expect(result).to eq(term: "ruby", limit: 3)
      expect(tool_instance.received).to eq(term: "ruby", limit: 3)
    end
  end

  describe "#execute" do
    it "raises NotImplementedError in the base class" do
      expect { described_class.new.execute }.to raise_error(
        NotImplementedError,
        "OmniAgent::Tool must implement #execute"
      )
    end
  end
end