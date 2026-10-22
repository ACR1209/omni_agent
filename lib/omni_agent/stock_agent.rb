module OmniAgent
  # Base class for stock agents: ready-made agents shipped inside the gem under
  # OmniAgent::StockAgents. Host apps use them as-is or subclass them to declare
  # their own `output` schema, extra prompt instructions, tools or model.
  #
  #   module OmniAgent::StockAgents
  #     class Summarizer < OmniAgent::StockAgent
  #       description "Summarizes documents"
  #       use_model "gpt-4o-mini"
  #     end
  #   end
  #
  # Prompts are read from lib/omni_agent/stock_agents/<stock_name>/ (override
  # with `prompts_path`) and rendered before any prompts the host app defines
  # for its subclass in app/agents/<agent_name>/.
  class StockAgent < Agent
    class << self
      def description(text = nil)
        @description = text if text
        @description || inherited_setting(:description) || "No description provided."
      end

      def stock_name(value = nil)
        @stock_name = value.to_sym if value
        @stock_name || (stock_definition? ? default_stock_name : inherited_setting(:stock_name))
      end

      def prompts_path(path = nil)
        @prompts_path = path.to_s if path
        @prompts_path || (stock_definition? ? File.join(OmniAgent::StockAgents.root, stock_name.to_s) : inherited_setting(:prompts_path))
      end

      private

      # True for the agents defined by the gem itself, as opposed to host-app
      # subclasses, which inherit the stock name and prompts of their parent.
      def stock_definition?
        name.to_s.start_with?("OmniAgent::StockAgents::")
      end

      def default_stock_name
        name.split("::").last
          .gsub(/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
          .gsub(/([a-z\d])([A-Z])/, "\\1_\\2")
          .downcase
          .to_sym
      end
    end

    private

    def prompt_template_paths(prompt_method)
      stock_directory = self.class.prompts_path
      stock_templates = stock_directory ? prompt_templates_in(stock_directory, prompt_method) : []

      stock_templates + super
    end
  end
end
