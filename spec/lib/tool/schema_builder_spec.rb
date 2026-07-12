require_relative "../../spec_helper"
require_relative "../../../lib/omni_agent/tool/schema_builder"

RSpec.describe OmniAgent::Tool::SchemaBuilder do
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
      expect(builder.required_fields).to eq([ "title" ])
    end

    it "adds integer and boolean fields, and skips required when false" do
      builder = described_class.new

      builder.integer(:count, required: false)
      builder.boolean(:published, description: "Whether it is published")

      expect(builder.properties).to eq(
        count: { type: "integer" },
        published: { type: "boolean", description: "Whether it is published" }
      )
      expect(builder.required_fields).to eq([ "published" ])
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
      expect(builder.required_fields).to eq([ "tags" ])
    end

    it "does not add field name to required_fields when required is false" do
      builder = described_class.new

      builder.array(:values, items_type: "integer", required: false)

      expect(builder.required_fields).to eq([])
    end

    it "allows defining nested object schema for array items" do
      builder = described_class.new

      builder.array(:users) do
        string :name
        integer :age, required: false
      end

      expect(builder.properties).to eq(
        users: {
          type: "array",
          items: {
            type: "object",
            properties: {
              name: { type: "string" },
              age: { type: "integer" }
            },
            required: [ "name" ],
            additionalProperties: false
          }
        }
      )

      expect(builder.required_fields).to eq([ "users" ])
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
      expect(builder.required_fields).to eq([ "filters" ])
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
          required: [ "name" ],
          additionalProperties: false
        }
      )
      expect(builder.required_fields).to eq([ "user" ])
    end

    it "respects required false for the top-level object field" do
      builder = described_class.new

      builder.hash(:settings, required: false) do
        boolean :enabled
      end

      expect(builder.required_fields).to eq([])
      expect(builder.properties[:settings][:required]).to eq([ "enabled" ])
    end
  end

  describe "#enum" do
    it "adds an enum field with string values" do
      builder = described_class.new

      builder.enum(:status, values: [ "active", "inactive" ], description: "User status")

      expect(builder.properties).to eq(
        status: {
          type: "string",
          enum: [ "active", "inactive" ],
          description: "User status"
        }
      )
      expect(builder.required_fields).to eq([ "status" ])
    end

    it "adds an enum field with integer values" do
      builder = described_class.new

      builder.enum(:level, values: [ 1, 2, 3 ], description: "Access level")

      expect(builder.properties).to eq(
        level: {
          type: "integer",
          enum: [ 1, 2, 3 ],
          description: "Access level"
        }
      )
      expect(builder.required_fields).to eq([ "level" ])
    end

    it "does not add field name to required_fields when required is false" do
      builder = described_class.new

      builder.enum(:priority, values: [ "low", "medium", "high" ], required: false)

      expect(builder.required_fields).to eq([])
    end

    it "normalizes symbol values to strings" do
      builder = described_class.new

      builder.enum(:status, values: [ :active, :inactive ])

      expect(builder.properties[:status]).to eq(
        type: "string",
        enum: [ "active", "inactive" ]
      )
    end

    it "raises when values are mixed types" do
      builder = described_class.new

      expect { builder.enum(:status, values: [ "active", 1 ]) }.to raise_error(
        ArgumentError, /enum values must all be the same type/
      )
    end

    it "raises when values are empty" do
      builder = described_class.new

      expect { builder.enum(:status, values: []) }.to raise_error(
        ArgumentError, /enum requires at least one value/
      )
    end

    it "raises for unsupported value types" do
      builder = described_class.new

      expect { builder.enum(:status, values: [ nil ]) }.to raise_error(
        ArgumentError, /unsupported enum value type/
      )
    end
  end

  describe "constraint kwargs" do
    it "maps string constraints to JSON Schema keywords" do
      builder = described_class.new

      builder.string(:name, min_length: 3, max_length: 40, pattern: /\A[a-z]+\z/, format: "email")

      expect(builder.properties[:name]).to eq(
        type: "string",
        minLength: 3,
        maxLength: 40,
        pattern: "\\A[a-z]+\\z",
        format: "email"
      )
    end

    it "maps integer min/max to minimum/maximum" do
      builder = described_class.new

      builder.integer(:level, min: 1, max: 5)

      expect(builder.properties[:level]).to eq(type: "integer", minimum: 1, maximum: 5)
    end

    it "adds a number field with float constraints" do
      builder = described_class.new

      builder.number(:ratio, min: 0.0, max: 1.0)

      expect(builder.properties[:ratio]).to eq(type: "number", minimum: 0.0, maximum: 1.0)
    end

    it "maps array min_items/max_items to minItems/maxItems" do
      builder = described_class.new

      builder.array(:tags, items_type: "string", min_items: 1, max_items: 10)

      expect(builder.properties[:tags]).to eq(
        type: "array",
        items: { type: "string" },
        minItems: 1,
        maxItems: 10
      )
    end

    it "omits constraint keys when not given" do
      builder = described_class.new

      builder.string(:name)

      expect(builder.properties[:name]).to eq(type: "string")
    end
  end

  describe "validate: procs" do
    it "captures a validator without leaking it into properties" do
      builder = described_class.new
      validator = ->(v) { v == v.downcase }

      builder.string(:slug, validate: validator)

      expect(builder.validators[:slug]).to eq(validator)
      expect(builder.properties[:slug]).to eq(type: "string")
    end

    it "captures validators for enum and hash fields" do
      builder = described_class.new
      enum_validator = ->(v) { true }
      hash_validator = ->(v) { true }

      builder.enum(:status, values: [ "active" ], validate: enum_validator)
      builder.hash(:filters, validate: hash_validator)

      expect(builder.validators[:status]).to eq(enum_validator)
      expect(builder.validators[:filters]).to eq(hash_validator)
    end
  end

  describe "#polymorphic" do
    it "expands into an enum type field and an id field, both required by default" do
      builder = described_class.new

      builder.polymorphic(:actor, types: [ "User", "Admin" ], description: "The actor")

      expect(builder.properties[:actor_type]).to eq(
        type: "string",
        enum: [ "User", "Admin" ],
        description: "The actor (type)"
      )
      expect(builder.properties[:actor_id]).to eq(
        type: "string",
        description: "The actor (id)"
      )
      expect(builder.required_fields).to eq([ "actor_type", "actor_id" ])
    end

    it "supports id_type: :integer" do
      builder = described_class.new

      builder.polymorphic(:actor, types: [ "User" ], id_type: :integer)

      expect(builder.properties[:actor_id][:type]).to eq("integer")
    end

    it "does not add fields to required_fields when required is false" do
      builder = described_class.new

      builder.polymorphic(:actor, types: [ "User" ], required: false)

      expect(builder.required_fields).to eq([])
    end

    it "supports the block form with per-field descriptions" do
      builder = described_class.new

      builder.polymorphic(:actor) do
        type values: [ "User", "Admin" ], description: "Class name"
        id type: :integer, description: "Primary key"
      end

      expect(builder.properties[:actor_type]).to eq(
        type: "string",
        enum: [ "User", "Admin" ],
        description: "Class name"
      )
      expect(builder.properties[:actor_id]).to eq(
        type: "integer",
        description: "Primary key"
      )
    end

    it "falls back to a plain string type field when no types: whitelist is given" do
      builder = described_class.new

      builder.polymorphic(:actor)

      expect(builder.properties[:actor_type]).to eq(type: "string")
    end

    it "records group metadata without leaking it into properties" do
      builder = described_class.new

      builder.polymorphic(:actor, types: [ "User" ], resolve: true)

      expect(builder.polymorphics[:actor]).to eq(
        type_field: :actor_type,
        id_field: :actor_id,
        types: [ "User" ],
        id_type: "string",
        resolve: true
      )
    end

    it "raises when resolve: true is given without types:" do
      builder = described_class.new

      expect { builder.polymorphic(:actor, resolve: true) }.to raise_error(
        ArgumentError, /polymorphic resolve: true requires types:/
      )
    end
  end
end
