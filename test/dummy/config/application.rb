require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f

    # For compatibility with applications that use this config
    config.action_controller.include_all_helpers = false

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    initializer "dummy.load_agents_manually" do
      Rails.autoloaders.main.ignore(Rails.root.join("app/agents"))
    end

    config.to_prepare do
      agent_files = Dir[Rails.root.join("app/agents/*/*.rb")].reject { |file| file.include?("/tools/") }.sort
      all_agent_files = Dir[Rails.root.join("app/agents/**/*.rb")].sort
      nested_files = all_agent_files - agent_files

      (agent_files + nested_files).each do |file|
        require_dependency file
      end
    end
  end
end
