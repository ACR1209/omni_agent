module OmniAgent
  module Streaming
    class Proxy
      def initialize(agent)
        @agent = agent
      end

      def method_missing(name, *args, **kwargs, &block)
        @agent.public_send(name, *args, **kwargs, &block)
      end

      def respond_to_missing?(name, include_private = false)
        @agent.respond_to?(name, include_private) || super
      end
    end
  end
end
