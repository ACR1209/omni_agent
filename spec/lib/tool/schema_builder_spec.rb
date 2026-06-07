require_relative "../../spec_helper"
require_relative "../../../lib/tool/schema_builder"

RSpec.describe OmniAgents::Tool::SchemaBuilder do
  describe "#initialize" do
    it "starts with empty properties and required_fields" do
      builder = described_class.new

      expect(builder.properties).to eq({})
      expect(builder.required_fields).to eq([])
    end
  end

  describe "primitive field helpers" do
    it "adds a string field with default required true" do
      builder = described_class.new

      builder.string(:title, description: "The title")

      expect(builder.properties).to eq(
        title: { type: "string", description: "The title" }
      )
      expect(builder.required_fields).to eq(["title"])
    end

    it "adds integer and boolean fields, and skips required when false" do
      builder = described_class.new

      builder.integer(:count, required: false)
      builder.boolean(:published, description: "Whether it is published")

      expect(builder.properties).to eq(
        count: { type: "integer" },
        published: { type: "boolean", description: "Whether it is published" }
      )
      expect(builder.required_fields).to eq(["published"])
    end
  end

  describe "#array" do
    it "adds an array field with item type and description" do
      builder = described_class.new

      builder.array(:tags, items_type: "string", description: "Tag names")

      expect(builder.properties).to eq(
        tags: {
          type: "array",
          items: { type: "string" },
          description: "Tag names"
        }
      )
      expect(builder.required_fields).to eq(["tags"])
    end

    it "does not add field name to required_fields when required is false" do
      builder = described_class.new

      builder.array(:values, items_type: "integer", required: false)

      expect(builder.required_fields).to eq([])
    end
  end

  describe "#hash" do
    it "adds a permissive object schema when no block is given" do
      builder = described_class.new

      builder.hash(:filters, description: "Filter options")

      expect(builder.properties).to eq(
        filters: {
          type: "object",
          description: "Filter options",
          additionalProperties: true
        }
      )
      expect(builder.required_fields).to eq(["filters"])
    end

    it "adds a nested object schema when a block is given" do
      builder = described_class.new

      builder.hash(:user) do
        string :name
        integer :age, required: false
      end

      expect(builder.properties).to eq(
        user: {
          type: "object",
          properties: {
            name: { type: "string" },
            age: { type: "integer" }
          },
          required: ["name"],
          additionalProperties: false
        }
      )
      expect(builder.required_fields).to eq(["user"])
    end

    it "respects required false for the top-level object field" do
      builder = described_class.new

      builder.hash(:settings, required: false) do
        boolean :enabled
      end

      expect(builder.required_fields).to eq([])
      expect(builder.properties[:settings][:required]).to eq(["enabled"])
    end
  end
end