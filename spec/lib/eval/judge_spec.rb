require_relative "../../spec_helper"
require_relative "../../../lib/omni_agent"

RSpec.describe OmniAgent::Eval::Judge do
  around do |example|
    previous_config = OmniAgent.instance_variable_get(:@configuration)
    OmniAgent.instance_variable_set(:@configuration, nil)
    example.run
    OmniAgent.instance_variable_set(:@configuration, previous_config)
  end

  it "scores output using an explicit provider name" do
    judge = described_class.new(provider: :mock_judge)

    verdict = judge.call(criteria: "is it friendly?", output: "Hello there!")

    expect(verdict[:score]).to eq(1.0)
    expect(verdict[:reason]).to eq("mock judge always approves")
  end

  it "falls back to the global eval_judge_provider config when no provider is given" do
    OmniAgent.configure { |config| config.eval_judge_provider = :mock_judge }

    judge = described_class.new
    verdict = judge.call(criteria: "is it friendly?", output: "Hello there!")

    expect(verdict[:score]).to eq(1.0)
  end

  it "falls back to the agent's own provider when nothing else is configured" do
    judge = described_class.new
    fallback_provider = OmniAgent::Providers::MockJudge.new

    verdict = judge.call(criteria: "is it friendly?", output: "Hello there!", fallback_provider: fallback_provider)

    expect(verdict[:score]).to eq(1.0)
  end
end

RSpec.describe OmniAgent::Eval::JudgeAssertion do
  it "passes when the judge score meets the threshold" do
    run = double("run", output: "Hello there!", agent: double("agent", provider: OmniAgent::Providers::MockJudge.new))
    assertion = described_class.new("is it friendly?", threshold: 0.5, provider: :mock_judge)

    outcome = assertion.call(run)

    expect(outcome).to be_passed
  end

  it "fails when the judge score is below the threshold" do
    run = double("run", output: "Hello there!", agent: double("agent", provider: OmniAgent::Providers::MockJudge.new))
    assertion = described_class.new("is it friendly?", threshold: 1.1, provider: :mock_judge)

    outcome = assertion.call(run)

    expect(outcome).not_to be_passed
  end
end
