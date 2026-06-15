# lib/omni_agent/railtie.rb
module OmniAgent
  class Railtie < ::Rails::Railtie
    initializer "omni_agent.remove_agents_from_zeitwerk", before: :setup_main_autoloader do
      agents_path = Rails.root.join("app", "agents")
      if agents_path.exist?
        Rails.autoloaders.main.ignore(agents_path)
      end
    end

    config.to_prepare do
      agents_dir = Rails.root.join("app", "agents")
      next unless agents_dir.exist?

      Dir.glob(agents_dir.join("concerns/**/*.rb")).each { |f| require_dependency f }

      Dir.glob(agents_dir.join("*")).each do |file|
        next unless File.directory?(file)
        next if File.basename(file) == "concerns"

        main_agent_file = File.join(file, "#{File.basename(file)}.rb")
        require_dependency main_agent_file if File.file?(main_agent_file)

        Dir.glob(File.join(file, "**/*.rb")).each do |sub_file|
          next if sub_file == main_agent_file
          require_dependency sub_file
        end
      end
    end
  end
end
