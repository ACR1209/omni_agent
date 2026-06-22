source "https://rubygems.org"

# Specify your gem's dependencies in omni_agent.gemspec.
gemspec

gem "puma"

gem "sqlite3"

gem "propshaft"

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

# Start debugger with binding.b [https://github.com/ruby/debug]
# gem "debug", ">= 1.0.0"

gem "ruby-lsp", "~> 0.26.9", groups: [ :development, :test ]

gem "rubocop", "~> 1.87", groups: [ :development, :test ]

gem "rspec", groups: [ :development, :test ]
gem "rspec-rails", groups: [ :development, :test ]

group :development, :test do
  gem "vcr"
  gem "webmock"
  gem "dotenv-rails"
  gem "openai", "~> 0.68.0"
end
