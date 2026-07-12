module TaskAgent::Tools
  class SetPriority < OmniAgent::Tool
    description "Sets the priority of a ticket."

    input do
      string :ticket, description: "The ticket identifier"
      enum :priority, values: [ "low", "medium", "high" ], description: "The priority level"
    end

    def execute(ticket:, priority:)
      "Ticket #{ticket} priority set to #{priority}"
    end
  end
end
