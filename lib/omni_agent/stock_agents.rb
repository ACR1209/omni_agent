module OmniAgent
  # Namespace for the stock (default) agents shipped with the gem. Each one is
  # an OmniAgent::StockAgent subclass in lib/omni_agent/stock_agents/<name>.rb,
  # with its prompt templates in lib/omni_agent/stock_agents/<name>/.
  module StockAgents
    def self.root
      File.expand_path("stock_agents", __dir__)
    end

    def self.all
      constants.sort.filter_map do |const_name|
        const = const_get(const_name)
        const if const.is_a?(Class) && const < OmniAgent::StockAgent
      end
    end

    def self.find(name)
      agent_class = all.find { |stock_agent| stock_agent.stock_name == name.to_sym }
      return agent_class if agent_class

      available = all.map(&:stock_name).join(", ")
      raise OmniAgent::UnknownStockAgentError,
            "Unknown stock agent #{name.inspect}. Available stock agents: #{available.empty? ? 'none' : available}"
    end
  end
end
