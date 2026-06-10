module OmniAgent
  class Configuration
    attr_accessor :default_provider, :default_model

    def initialize
      @default_provider = :openai
      @default_model = "gpt-4o-mini"
    end
  end
end