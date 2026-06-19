require "omni_agent/version"
require "omni_agent/engine" if defined?(Rails)
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect("openai" => "OpenAI")
loader.ignore(File.expand_path("generators", __dir__))
loader.setup

# errors.rb defines top-level aliases (OmniAgent::MissingDependencyError, etc.)
# that Zeitwerk cannot autoload, since they don't map to a file path of their
# own. Force it to load eagerly so the aliases exist regardless of which
# constant is referenced first.
require "omni_agent/errors"


module OmniAgent
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end
  end
end
