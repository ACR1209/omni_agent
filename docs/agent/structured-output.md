<!-- Generated from omniagent-docs/docs/agent/structured-output.mdx by `bundle exec rake docs:sync`. Do not edit by hand. -->
<!-- Online version: https://omniagent.activetaskers.com/docs/agent/structured-output -->

# Structured Output

Declare an `output` block to make an agent return a validated object instead of free text. It uses the same DSL as a tool's [`input`](../tools.md#input-schema-dsl):

```ruby
class InvoiceAgent < OmniAgent::Agent
  use_model "gpt-4o-mini"

  output do
    string :invoice_number, description: "Invoice identifier as printed"
    number :total, min: 0
    enum :currency, values: %w[USD EUR]
    array :line_items do
      string :description
      number :amount
    end
  end
end

response = InvoiceAgent.new.run(invoice_text)
response.structured_output
# => { invoice_number: "A-1042", total: 120.5, currency: "USD", line_items: [ { description: "Paper", amount: 120.5 } ] }
response.answer # the raw JSON string returned by the model
```

## How It Works

1. The schema is sent to the provider with every request. OpenAI and Ollama receive it as a `json_schema` `response_format`. Providers that don't support structured output natively get the schema in the system prompt instead (see [Custom Providers](#custom-providers)).
2. When the model gives its final answer, the JSON is parsed (a surrounding ` ```json ` fence is tolerated) and validated with the same rules as tool input: required fields, `enum` values, `min`/`max`, `min_length`/`max_length`, `pattern`, `min_items`/`max_items` and custom `validate:` procs. On top of that, every top-level value must match its declared type (`string`, `integer`, `number`, `boolean`, `array` or `hash`), so `total: "120.5"` is rejected for a `number`. Keys not declared in the schema are dropped, and `null` for an optional field is treated as absent.
3. The result is exposed as `response.structured_output`, a hash with symbol keys. It is set before `after_generation` callbacks run, so callbacks can read it from `payload[:response]`.

Type and constraint checks apply to top-level fields; nested objects are described to the model but not validated field by field.

## Handling Errors

If the model returns invalid JSON, the object fails validation, or a polymorphic `resolve: true` field can't be resolved, `run` raises `OmniAgent::StructuredOutputError`. The error keeps the raw model output so you can log it, retry or repair it without paying for the generation again:

```ruby
begin
  InvoiceAgent.new.run(invoice_text)
rescue OmniAgent::StructuredOutputError => e
  Rails.logger.warn("Invalid invoice output: #{e.message}\n#{e.content}")
  e.response # the full OmniAgent::Providers::Response
end
```

## Strict Mode

OpenAI's strict structured outputs are enabled automatically when the schema allows it: every field is required, every `hash` has a block, and no `min_length`/`max_length` is used. Otherwise the schema is sent with `strict: false`, so the model only treats it as guidance; in that case the schema is also added to the system prompt, and OmniAgent's validation enforces it.

## Custom Providers

A provider receives the schema as the `output_schema:` keyword of `#chat` (an `OmniAgent::Schema`; call `#json_schema` on it) only when it declares support:

```ruby
class MyProvider < OmniAgent::Providers::Base
  def supports_structured_output?
    true
  end

  def chat(messages:, tools: [], stream: nil, output_schema: nil, **options)
    # send output_schema.json_schema in the provider's own format
  end
end
```

Providers that don't (the default in `OmniAgent::Providers::Base`) never receive `output_schema:`; the agent appends the JSON schema to the system prompt and asks for a JSON-only answer instead.

## Inheritance

`output` is inherited by subclasses, and a subclass can declare its own `output` block to replace it. This is how [stock agents](../stock-agents.md) let each project decide which fields to extract.

## Mock Provider

With `provider :mock`, an agent that declares `output` gets placeholder JSON built from the schema (the first `enum` value, `min` for numbers, lorem ipsum for strings), so you can wire up code that reads `structured_output` before calling a real model.

The placeholders can't satisfy everything. If a field has a `pattern:` the lorem text doesn't match, a custom `validate:` proc that rejects the placeholder, or is a polymorphic field with `resolve: true`, the mock raises an `OmniAgent::Error` naming the field. In those tests, stub the provider's `#chat` response instead.
