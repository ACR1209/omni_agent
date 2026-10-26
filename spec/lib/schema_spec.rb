require_relative "../spec_helper"
require_relative "../../lib/omni_agent"

RSpec.describe OmniAgent::Schema do
  describe ".build" do
    it "builds the JSON schema from the Tool input DSL" do
      schema = described_class.build do
        string :name, description: "Customer name"
        integer :age, required: false
      end

      expect(schema.json_schema).to eq(
        type: "object",
        properties: {
          name: { type: "string", description: "Customer name" },
          age: { type: "integer" }
        },
        required: [ "name" ],
        additionalProperties: false
      )
    end
  end

  describe "#parse" do
    let(:schema) do
      described_class.build do
        string :name, min_length: 2
        enum :status, values: %w[paid due]
        number :total, min: 0, validate: ->(value) { value < 1_000 }
      end
    end

    it "returns symbol-keyed values and drops keys outside the schema" do
      expect(schema.parse("name" => "Ana", "status" => "paid", "total" => 12.5, "extra" => true))
        .to eq(name: "Ana", status: "paid", total: 12.5)
    end

    it "validates required fields, enums, constraints and custom validators" do
      expect { schema.parse(status: "paid", total: 1) }.to raise_error(ArgumentError, /missing required argument\(s\): name/)
      expect { schema.parse(name: "Ana", status: "void", total: 1) }.to raise_error(ArgumentError, /invalid value for status/)
      expect { schema.parse(name: "A", status: "paid", total: 1) }.to raise_error(ArgumentError, /at least 2 characters/)
      expect { schema.parse(name: "Ana", status: "paid", total: -1) }.to raise_error(ArgumentError, /total must be >= 0/)
      expect { schema.parse(name: "Ana", status: "paid", total: 5_000) }.to raise_error(ArgumentError, /invalid value for total/)
    end

    it "checks top-level types only in #parse_typed" do
      typed = described_class.build do
        string :name
        integer :count
        number :total
        boolean :paid
        array :tags
        hash :meta
        string :nickname, required: false
      end
      valid = { name: "Ana", count: 1, total: 2, paid: false, tags: [], meta: {}, nickname: nil }

      expect(typed.parse_typed(valid)).to eq(valid.except(:nickname))
      expect(typed.parse(valid.merge(count: "1"))).to include(count: "1")
      expect { typed.parse_typed(valid.merge(count: "1")) }
        .to raise_error(ArgumentError, /count must be of type integer, got "1"/)
      expect { typed.parse_typed(valid.merge(count: 1.5)) }.to raise_error(ArgumentError, /count must be of type integer/)
      expect { typed.parse_typed(valid.merge(paid: "false")) }.to raise_error(ArgumentError, /paid must be of type boolean/)
      expect { typed.parse_typed(valid.merge(tags: "a")) }.to raise_error(ArgumentError, /tags must be of type array/)
      expect { typed.parse_typed(valid.merge(meta: [])) }.to raise_error(ArgumentError, /meta must be of type object/)
      expect { typed.parse_typed(valid.merge(name: nil)) }.to raise_error(ArgumentError, /name must be of type string, got nil/)
    end

    it "rejects values that are not an object" do
      expect { schema.parse([ 1, 2 ]) }.to raise_error(ArgumentError, /expected an object, got Array/)
    end
  end

  describe "#strict_compatible?" do
    it "is true when every field is required and objects are closed" do
      schema = described_class.build do
        string :name
        array :items do
          string :sku
        end
        hash :address do
          string :city
        end
      end

      expect(schema.strict_compatible?).to be(true)
    end

    it "is false with optional fields, free-form hashes or length constraints" do
      optional = described_class.build { string :name, required: false }
      free_form = described_class.build { hash :metadata }
      nested_optional = described_class.build do
        array :items do
          string :sku, required: false
        end
      end
      length_limited = described_class.build { string :code, max_length: 4 }

      expect([ optional, free_form, nested_optional, length_limited ].map(&:strict_compatible?)).to all(be(false))
    end
  end
end
