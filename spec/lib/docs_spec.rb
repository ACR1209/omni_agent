require_relative "../spec_helper"
require_relative "../../lib/omni_agent"
require_relative "../../rakelib/support/docs_sync"

RSpec.describe OmniAgent::Docs do
  describe ".read" do
    it "returns the index by default" do
      expect(described_class.read).to start_with("# OmniAgent Documentation")
    end

    it "reads a nested page with or without the .md extension" do
      expect(described_class.read("mcp/authentication")).to include("# Authentication")
      expect(described_class.read("mcp/authentication.md")).to include("# Authentication")
    end

    it "returns nil for unknown pages, including paths outside the docs root" do
      expect(described_class.read("nope")).to be_nil
      expect(described_class.read("../README")).to be_nil
    end
  end

  describe ".pages" do
    it "lists every bundled page" do
      expect(described_class.pages).to include("index", "intro", "tools", "agent/delegation")
    end
  end

  describe "bundled files" do
    it "are in sync with omniagent-docs (run `bundle exec rake docs:sync`)" do
      expected = DocsSync.build
      actual = described_class.pages.to_h { |page| [ "#{page}.md", described_class.read(page) ] }

      expect(actual.keys).to match_array(expected.keys)
      expected.each { |path, contents| expect(actual[path]).to eq(contents), "docs/#{path} is stale" }
    end

    it "only link to pages that exist" do
      described_class.pages.each do |page|
        dir = File.dirname(File.join(described_class.root, page))
        described_class.read(page).scan(/\]\(([^)#\s]+\.md)(?:#[^)]*)?\)/).flatten.each do |link|
          expect(File).to exist(File.expand_path(link, dir)), "broken link #{link} in docs/#{page}.md"
        end
      end
    end
  end
end
