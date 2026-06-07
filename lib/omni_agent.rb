require "omni_agent/version"
require "omni_agent/engine" if defined?(Rails)
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect("openai" => "OpenAI")
loader.setup


module OmniAgent
  # Your code goes here...
end
