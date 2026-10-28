<!-- Generated from omniagent-docs/docs/stock-agents.mdx by `bundle exec rake docs:sync`. Do not edit by hand. -->
<!-- Online version: https://omniagent.activetaskers.com/docs/stock-agents -->

# Stock Agents

Stock agents are ready-made agents shipped with the gem under `OmniAgent::StockAgents`. They bring their own prompt, model settings and tools; your project subclasses one and declares the [structured output](agent/structured-output.md) it needs.

## Using a Stock Agent

```bash
rails generate omni_agent:stock_agent InvoiceOcr --from=ocr --fields=invoice_number:string total:number paid:boolean
```

Generates:

```ruby
# app/agents/invoice_ocr.rb
class InvoiceOcr < OmniAgent::StockAgents::OCR
  output do
    string :invoice_number
    number :total
    boolean :paid
  end
end
```

and an optional `app/agents/invoice_ocr/prompt.md.erb`. Edit the `output` block with the full DSL (descriptions, `required: false`, enums, nested arrays and hashes), then run it like any agent:

```ruby
InvoiceOcr.new.run(document_text).structured_output
# => { invoice_number: "A-1042", total: 120.5, paid: true }
```

A subclass inherits everything from the stock agent — provider, model, `options`, tags, callbacks, tools and prompts — and can override any of it with the usual DSL (`use_model`, `options`, `output`, ...). To replace one of the stock agent's tools, define a tool with the same name under your subclass's `Tools` namespace (e.g. `InvoiceOcr::Tools::Extract`). See [Inheritance](agent/provider.md#inheritance) for how `use_model` interacts with an inherited provider.

### Prompts

The stock agent's prompt (shipped inside the gem) is rendered first. If your subclass has `app/agents/<agent_name>/prompt.md.erb`, it is appended after it, so you can add project-specific instructions without copying the stock prompt. The same applies to [run alias](agent/run-entrypoints.md) prompt files.

### Listing Stock Agents

```ruby
OmniAgent::StockAgents.all          # => [OmniAgent::StockAgents::OCR, ...]
OmniAgent::StockAgents.find(:ocr)   # => OmniAgent::StockAgents::OCR
OmniAgent::StockAgents.find(:nope)  # raises OmniAgent::UnknownStockAgentError
```

## Adding a Stock Agent to the Gem

From the gem repository:

```bash
bin/rake "stock_agent:new[ocr,OCR]"
```

The second argument is only needed when the class name isn't the camelized file name; the task then prints the Zeitwerk inflection to add in `lib/omni_agent.rb`. It creates:

```text
lib/omni_agent/stock_agents/
├── ocr.rb                 # class OmniAgent::StockAgents::OCR < OmniAgent::StockAgent
└── ocr/
    ├── prompt.md.erb      # default prompt
    └── tools/             # optional: OmniAgent::StockAgents::OCR::Tools::*
spec/lib/stock_agents/ocr_spec.rb
```

A stock agent is a regular agent with a few extra class methods:

```ruby
module OmniAgent
  module StockAgents
    class OCR < OmniAgent::StockAgent
      description "Extracts structured data from documents"
      use_model "gpt-4o"

      # Default output, used when the host app doesn't declare its own.
      output do
        string :text, description: "Full text of the document"
      end
    end
  end
end
```

* **`description`**: Human-readable summary of what the stock agent does.
* **`stock_name`**: Name used by `OmniAgent::StockAgents.find` and the generator's `--from`. Defaults to the underscored class name (`OCR` → `:ocr`).
* **`prompts_path`**: Directory with the stock prompt templates. Defaults to `lib/omni_agent/stock_agents/<stock_name>/`.
