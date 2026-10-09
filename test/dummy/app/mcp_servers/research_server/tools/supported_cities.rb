module ResearchServer::Tools
  class SupportedCities < OmniAgent::Tool
    title "Supported cities"
    description "Lists the cities with detailed weather data."
    annotations read_only: true, idempotent: true, open_world: false

    def execute(**)
      { cities: [ "Quito", "Guayaquil", "Cuenca" ] }
    end
  end
end
