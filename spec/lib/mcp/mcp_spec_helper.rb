require_relative "../../spec_helper"
require_relative "../../../lib/omni_agent"
require "active_support/core_ext/string/inflections"
require "json"
require "rack"
require "stringio"

module MCPSpecTools
  class Echo < OmniAgent::Tool
    title "Echo"
    description "Echoes text back."
    annotations read_only: true, idempotent: true

    input do
      string :text, description: "Text to echo", max_length: 10
    end

    def execute(text:)
      "echo: #{text}"
    end
  end

  class Admin < OmniAgent::Tool
    description "Admin-only tool."
    tags :admin

    def execute(**)
      "admin"
    end
  end

  class Whoami < OmniAgent::Tool
    description "Returns the context it was called with."

    def execute(**)
      { principal: context[:mcp_principal].to_s, current_user: context[:current_user].to_s }
    end
  end

  class Boom < OmniAgent::Tool
    description "Always fails."

    def execute(**)
      raise "kaboom"
    end
  end
end
