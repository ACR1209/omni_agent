module TaskAgent::Tools
  class SetEstimate < OmniAgent::Tool
    description "Sets the estimated hours to complete a ticket."

    input do
      string :ticket, description: "The ticket identifier"
      integer :hours, description: "Estimated hours, must be between 1 and 40", min: 1, max: 40
    end

    def execute(ticket:, hours:)
      "Ticket #{ticket} estimate set to #{hours}h"
    end
  end
end
