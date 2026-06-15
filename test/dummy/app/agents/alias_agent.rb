class AliasAgent < OmniAgent::Agent
  provider :openai, model: "gpt-4o-mini"

  attr_reader :last_entrypoint

  def summarize
    @last_entrypoint = :summarize
    @message = "legacy summarize behavior"
  end

  def classify
    @last_entrypoint = :classify
    @message = "legacy classify behavior"
  end
end
