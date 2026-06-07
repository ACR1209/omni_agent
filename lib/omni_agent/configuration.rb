module OmniAgent
  class Configuration
    attr_accessor :default_provider

    def initialize
      @default_provider = :openai
    end
  end
end