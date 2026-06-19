module ResearchAgent::Tools
  class GetWeather < OmniAgent::Tool
    description "Retrieves current weather details."

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
