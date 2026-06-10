class ResearchAgent < OmniAgent::Agent
  provider :openai, model: "gpt-4o-mini"
  before_generation :log_before
  before_generation :add_variable_to_context
  after_generation :log_after

  def add_variable_to_context
    @user_name = "Test User"
  end

  def log_before
    @before_log ||= []
    @before_log << "before_generation called"
  end

  def log_after
    @after_log ||= []
    @after_log << "after_generation called"
  end
end
