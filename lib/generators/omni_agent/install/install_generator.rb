require "rails/generators"
require "fileutils"

module OmniAgent
  module Generators
    class InstallGenerator < Rails::Generators::Base
      desc "Creates OmniAgent base directories in app/agents"

      def create_agents_root
        agents_root = File.join(destination_root, "app", "agents")
        FileUtils.mkdir_p(agents_root)
        say_status :create, agents_root
      end

      def show_next_steps
        say "OmniAgent install complete."
        say "Next: rails generate omni_agent:agent SupportAgent --with-tools Tool1 Tool2"
      end
    end
  end
end
