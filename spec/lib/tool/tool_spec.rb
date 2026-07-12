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

      expect(klass.tags).to eq([ :math, :person ])
    end

    it "returns current tags when called with no arguments" do
      klass = Class.new(described_class)
      klass.tags(:math)

      expect(klass.tags).to eq([ :math ])
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
        required: [ "query", "filters" ],
        additionalProperties: false
      )
    end
  end

  describe ".invoke" do
    it "passes symbolized keyword arguments to #execute" do
      klass = Class.new(described_class) do
        input do
          integer :limit
          string :term
        end

        attr_reader :received

        def execute(**args)
          @received = args
        end
      end

      tool_instance = klass.new
      allow(klass).to receive(:new).and_return(tool_instance)

      result = tool_instance.invoke("term" => "ruby", "limit" => 3)

      expect(result).to eq(term: "ruby", limit: 3)
      expect(tool_instance.received).to eq(term: "ruby", limit: 3)
    end

    it "filters out keys that are not defined in the schema" do
      klass = Class.new(described_class) do
        input do
          string :query
        end

        attr_reader :received

        def execute(**args)
          @received = args
        end
      end

      tool_instance = klass.new
      allow(klass).to receive(:new).and_return(tool_instance)

      result = tool_instance.invoke("query" => "ruby", "unexpected" => 123)

      expect(result).to eq(query: "ruby")
      expect(tool_instance.received).to eq(query: "ruby")
    end

    it "raises when a required argument is missing" do
      klass = Class.new(described_class) do
        input do
          string :query
        end

        def execute(**args); end
      end

      tool_instance = klass.new

      expect { tool_instance.invoke({}) }.to raise_error(
        ArgumentError, /missing required argument\(s\): query/
      )
    end

    it "raises when an enum argument has an invalid value" do
      klass = Class.new(described_class) do
        input do
          enum :status, values: [ "active", "inactive" ]
        end

        def execute(**args); end
      end

      tool_instance = klass.new

      expect { tool_instance.invoke("status" => "unknown") }.to raise_error(
        ArgumentError, /invalid value for status/
      )
    end

    it "accepts a valid enum value" do
      klass = Class.new(described_class) do
        input do
          enum :status, values: [ "active", "inactive" ]
        end

        attr_reader :received

        def execute(**args)
          @received = args
        end
      end

      tool_instance = klass.new

      result = tool_instance.invoke("status" => "active")

      expect(result).to eq(status: "active")
    end
  end

  describe ".stops_generation" do
    it "defaults to false" do
      klass = Class.new(described_class)

      expect(klass.stops_generation?).to be(false)
    end

    it "can be enabled via DSL" do
      klass = Class.new(described_class) do
        stops_generation
      end

      expect(klass.stops_generation?).to be(true)
    end

    it "can be explicitly disabled" do
      klass = Class.new(described_class) do
        stops_generation
        stops_generation false
      end

      expect(klass.stops_generation?).to be(false)
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

  describe "#stops_generation?" do
    it "returns true if stop_generation! has been called" do
      tool_instance = described_class.new

      expect(tool_instance.stops_generation?).to be(false)

      tool_instance.stop_generation!

      expect(tool_instance.stops_generation?).to be(true)
    end

    it "does not affect the class-level stops_generation?" do
      klass = Class.new(described_class)

      expect(klass.stops_generation?).to be(false)

      instance = klass.new
      instance.stop_generation!

      expect(instance.stops_generation?).to be(true)
      expect(klass.stops_generation?).to be(false)
    end

    it "returns false if stop_generation! has not been called" do
      tool_instance = described_class.new

      expect(tool_instance.stops_generation?).to be(false)
    end
  end
end
