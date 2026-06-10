require_relative "lib/omni_agent/version"

Gem::Specification.new do |spec|
  spec.name        = "omni_agent"
  spec.version     = OmniAgent::VERSION
  spec.authors     = [ "ACR1209" ]
  spec.email       = [ "andrescoronel1209@gmail.com" ]
  spec.homepage    = "https://github.com/ACR1209/omni_agent"
  spec.summary     = "Rails engine for building AI agents with tools."
  spec.description = "OmniAgent provides a Rails-native framework for defining AI agents, tool schemas, prompt templates, callbacks, and provider-backed generation workflows."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ACR1209/omni_agent"
  spec.metadata["changelog_uri"] = "https://github.com/ACR1209/omni_agent/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md", "CHANGELOG.md"]
  end

  spec.add_dependency "rails", ">= 7.0"
  spec.add_dependency "zeitwerk", "~> 2.6"
end
