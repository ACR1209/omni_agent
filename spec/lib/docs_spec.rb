require_relative "../spec_helper"
require "tmpdir"
require_relative "../../lib/omni_agent"
require_relative "../../rakelib/support/docs_sync"

# docs/ isn't committed (it's generated before `rake build`), so these specs
# work on DocsSync's output in a temporary directory.
RSpec.describe OmniAgent::Docs do
  before do
    @dir = Dir.mktmpdir
    DocsSync.write!(@dir)
    allow(described_class).to receive(:root).and_return(@dir)
  end

  after { FileUtils.remove_entry(@dir) }

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
end

RSpec.describe DocsSync do
  # GitHub-style anchors of every heading in a Markdown document, ignoring
  # headings inside fenced code blocks. Repeated headings get -1, -2...
  def anchors(markdown)
    seen = Hash.new(0)
    markdown.gsub(/^```.*?^```/m, "").scan(/^#+ (.+)$/).flatten.map do |heading|
      anchor = described_class.heading_anchor(heading.strip)
      count = seen[anchor]
      seen[anchor] += 1
      count.zero? ? anchor : "#{anchor}-#{count}"
    end
  end

  describe ".build" do
    it "only links to pages, headings and files that exist" do
      files = described_class.build

      files.each do |path, contents|
        next unless path.end_with?(".md")

        contents.scan(/\]\(([^)\s]+)\)/).flatten.each do |link|
          next if link.match?(/\A[a-z]+:/)

          target, anchor = link.split("#", 2)
          target = target.empty? ? path : (Pathname.new(File.dirname(path)) + target).cleanpath.to_s
          expect(files).to have_key(target), "broken link #{link} in docs/#{path}"
          next unless anchor && target.end_with?(".md")

          expect(anchors(files[target])).to include(anchor), "missing anchor #{link} in docs/#{path}"
        end
      end
    end

    context "with a folder without _category_.json and an image" do
      before do
        @dir = Dir.mktmpdir
        FileUtils.mkdir_p(File.join(@dir, "guides", "img"))
        File.write(File.join(@dir, "intro.mdx"), "# Intro\n\nSee [the guide](./guides/setup.mdx) and [Guides](/docs/category/guides).\n")
        File.write(File.join(@dir, "guides", "setup.mdx"), "# Setup\n\nLike this:\n\n![Diagram](./img/flow.png)\n")
        File.binwrite(File.join(@dir, "guides", "img", "flow.png"), "PNG")
        stub_const("DocsSync::SOURCE", @dir)
      end

      after { FileUtils.remove_entry(@dir) }

      it "treats the folder as a category and copies the image" do
        files = described_class.build

        expect(files["guides/img/flow.png"]).to eq("PNG")
        expect(files["guides/setup.md"]).to include("![Diagram](./img/flow.png)")
        expect(files["intro.md"]).to include("[the guide](guides/setup.md)", "[Guides](index.md#guides)")
        expect(files["index.md"]).to include("### guides", "* [Setup](guides/setup.md)")
      end
    end
  end
end
