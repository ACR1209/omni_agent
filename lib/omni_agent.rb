require "omni_agent/version"
require "omni_agent/engine" if defined?(Rails)
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect("openai" => "OpenAI")
loader.ignore(File.expand_path("generators", __dir__))
loader.setup


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
