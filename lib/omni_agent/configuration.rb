module OmniAgent
  class Configuration
    attr_accessor :default_provider, :default_model, :max_retries, :retry_base_delay, :max_tool_iterations,
                  :max_delegation_depth, :eval_judge_provider, :eval_judge_model, :eval_cache_enabled, :eval_cache_path

    def initialize
      @default_provider = :openai
      @default_model = "gpt-4o-mini"
      @max_retries = 3
      @retry_base_delay = 0.5
      @max_tool_iterations = 10
      @max_delegation_depth = 5
      @eval_judge_provider = nil
      @eval_judge_model = nil
      @eval_cache_enabled = true
      @eval_cache_path = "tmp/omni_agent_eval_cache.json"
    end
  end
end
