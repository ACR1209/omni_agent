require "omni_agent/version"
require "omni_agent/engine" if defined?(Rails)
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "openai" => "OpenAI", "cli" => "CLI", "mcp" => "MCP",
  "oauth" => "OAuth", "jwt_verifier" => "JWTVerifier", "http_client" => "HTTPClient",
  "pdf" => "PDF", "html" => "HTML"
)
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

    # Embeds a String into one vector, or an Array of Strings into one vector
    # per text. Index and query with the same provider and model, or the
    # vectors are not comparable.
    def embed(input, provider: nil, model: nil)
      provider_name = provider || configuration.embedding_provider || configuration.default_provider
      vectors = Providers.fetch(provider_name).new.embed(Array(input), model: model || configuration.embedding_model)

      input.is_a?(Array) ? vectors : vectors.first
    end
  end
end
