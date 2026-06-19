module OmniAgent
  class Configuration
    attr_accessor :default_provider, :default_model, :max_retries, :retry_base_delay, :max_tool_iterations

    def initialize
      @default_provider = :openai
      @default_model = "gpt-4o-mini"
      @max_retries = 3
      @retry_base_delay = 0.5
      @max_tool_iterations = 10
    end
  end
end