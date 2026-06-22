class ResearchAgentEval < OmniAgent::Eval
  agent ResearchAgent

  eval_case "looks up the weather in Quito" do
    input "What's the weather in Quito?"
    expect_tool_call :GetWeather, with: { city: "Quito" }
    expect_output to_include: "16°C"
  end

  eval_case "is friendly and on-topic" do
    input "What's the weather in Quito?"
    judge "Is the response on-topic and does it answer the weather question?", threshold: 0.7
  end

  golden_set File.expand_path("golden/research_agent.yml", __dir__) do |row|
    expect_tool_call row[:tool_call][:name], with: row[:tool_call][:args]
    expect_output to_include: row[:expected_output]
  end
end
