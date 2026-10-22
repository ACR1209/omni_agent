# Development-only task (rakelib/ is not packaged with the gem) that scaffolds
# a new stock agent inside the gem:
#
#   bin/rake "stock_agent:new[ocr]"
#   bin/rake "stock_agent:new[ocr,OCR]"   # class name that camelize can't infer
require "fileutils"
require "active_support/core_ext/string/inflections"

namespace :stock_agent do
  desc "Scaffold a stock agent in lib/omni_agent/stock_agents (args: name[,ClassName])"
  task :new, [ :name, :class_name ] do |_task, args|
    name = args[:name].to_s.strip.underscore
    abort "Usage: rake \"stock_agent:new[name,ClassName]\"" if name.empty?

    class_name = args[:class_name].to_s.strip
    class_name = name.camelize if class_name.empty?
    root = File.expand_path("..", __dir__)

    files = {
      "lib/omni_agent/stock_agents/#{name}.rb" => <<~RUBY,
        module OmniAgent
          module StockAgents
            class #{class_name} < OmniAgent::StockAgent
              description "TODO: describe what the #{name} stock agent does"
              use_model "gpt-4o-mini"

              # Default structured output. Host apps override it by subclassing
              # and declaring their own `output do ... end` block.
              output do
                string :result, description: "TODO: describe the result"
              end
            end
          end
        end
      RUBY
      "lib/omni_agent/stock_agents/#{name}/prompt.md.erb" => <<~ERB,
        You are the #{class_name} stock agent. TODO: write the default instructions.
      ERB
      "spec/lib/stock_agents/#{name}_spec.rb" => <<~RUBY
        require_relative "../../spec_helper"
        require_relative "../../../lib/omni_agent"
        require "active_support/core_ext/string/inflections"

        RSpec.describe OmniAgent::StockAgents::#{class_name} do
          it "is registered as a stock agent" do
            expect(OmniAgent::StockAgents.find(:#{name})).to eq(described_class)
          end

          it "returns structured output validated against its output schema" do
            response = Class.new(described_class) { provider :mock }.new.run("input")

            expect(response.structured_output).to be_a(Hash)
          end
        end
      RUBY
    }

    files.each do |relative_path, content|
      path = File.join(root, relative_path)
      abort "#{relative_path} already exists" if File.exist?(path)

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      puts "create  #{relative_path}"
    end

    unless class_name == name.camelize
      puts "\nAdd the inflection to lib/omni_agent.rb so Zeitwerk can load it:"
      puts "  loader.inflector.inflect(\"#{name}\" => \"#{class_name}\")"
    end
  end
end
