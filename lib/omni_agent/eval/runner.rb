require "json"

module OmniAgent
  class Eval
    module Runner
      def self.run(eval_case, agent_class)
        agent = agent_class.new

        cache_key = Cache.key_for(
          agent_class: agent_class,
          run_alias: eval_case.configured_run_alias,
          input: eval_case.configured_input,
          context: eval_case.configured_context
        )

        cached = Cache.fetch(cache_key) { invoke_agent(agent, eval_case) }
        run = Run.new(output: cached["output"], tool_calls: normalize_tool_calls(cached["tool_calls"]), agent: agent)

        outcomes = eval_case.configured_assertions.map { |assertion| assertion.call(run) }
        CaseResult.new(case_name: eval_case.name, outcomes: outcomes)
      end

      def self.invoke_agent(agent, eval_case)
        response = if eval_case.configured_run_alias
          agent.public_send(eval_case.configured_run_alias, eval_case.configured_input, context: eval_case.configured_context)
        else
          agent.run(eval_case.configured_input, context: eval_case.configured_context)
        end

        { "output" => response.answer.to_s, "tool_calls" => extract_tool_calls(response) }
      end

      def self.extract_tool_calls(response)
        response.generated_messages
          .select { |message| (message[:role] || message["role"]) == "assistant" }
          .flat_map { |message| message[:tool_calls] || message["tool_calls"] || [] }
          .map { |tool_call| extract_tool_call(tool_call) }
      end

      def self.extract_tool_call(tool_call)
        function = tool_call[:function] || tool_call["function"] || {}
        name = function[:name] || function["name"]
        raw_arguments = function[:arguments] || function["arguments"]

        { "name" => name, "arguments" => parse_arguments(raw_arguments) }
      end

      def self.parse_arguments(raw_arguments)
        return {} if raw_arguments.nil?

        parsed = raw_arguments.is_a?(String) ? JSON.parse(raw_arguments) : raw_arguments
        parsed.transform_keys(&:to_s)
      rescue JSON::ParserError
        {}
      end

      def self.normalize_tool_calls(tool_calls)
        Array(tool_calls).map do |tool_call|
          { name: tool_call["name"], arguments: (tool_call["arguments"] || {}).transform_keys(&:to_sym) }
        end
      end

      private_class_method :invoke_agent, :extract_tool_calls, :extract_tool_call, :parse_arguments, :normalize_tool_calls
    end
  end
end
