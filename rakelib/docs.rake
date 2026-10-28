# Development-only task (rakelib/ is not packaged with the gem) that regenerates
# the plain-Markdown docs shipped in docs/ from the Docusaurus site:
#
#   bundle exec rake docs:sync
require_relative "support/docs_sync"

namespace :docs do
  desc "Regenerate docs/ (bundled in the gem) from omniagent-docs/docs"
  task :sync do
    written = DocsSync.write!
    puts "Wrote #{written.size} files to docs/"
  end
end
