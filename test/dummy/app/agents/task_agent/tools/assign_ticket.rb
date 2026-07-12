module TaskAgent::Tools
  class AssignTicket < OmniAgent::Tool
    description "Assigns a ticket to an actor, who is either a User or an Admin."

    input do
      string :ticket, description: "The ticket identifier"
      polymorphic :actor,
        types: [ "User", "Admin" ],
        description: "Who the ticket is assigned to",
        resolve: true
    end

    def execute(ticket:, actor:)
      "Ticket #{ticket} assigned to #{actor.class.name} #{actor.name} (##{actor.id})"
    end
  end
end
