module ResearchAgent::Tools
  class GetWeather < OmniAgent::Tool
    title "Get weather"
    description "Retrieves current weather details."
    annotations read_only: true, destructive: false, idempotent: true, open_world: true

    input do
      string :city, description: "The name of the city"
    end

    def execute(city:)
      if city.downcase == "quito"
        "16°C and sunny in Quito"
      else
        "Sunny in #{city}"
      end
    end
  end
end
