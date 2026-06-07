module OmniAgent
  class Agent
    attr_reader :provider

    class << self
      def provider(name, **options)
        if configured_with_use_model?
          raise OmniAgent::Error, "Cannot combine `provider` and `use_model` in the same agent. Use either `provider ..., model: ...` or `use_model ...`."
        end

        @provider_name = name
        @provider_options = options
      end

      def options(**options)
        @model_options = configured_model_options.merge(options)
      end

      def use_model(name)
        if configured_provider_name || configured_provider_options.any?
          raise OmniAgent::Error, "Cannot combine `provider` and `use_model` in the same agent. Use either `provider ..., model: ...` or `use_model ...`."
        end

        @configured_with_use_model = true
        @provider_options = { model: name }
      end

      def configured_provider_name; @provider_name; end
      def configured_provider_options; @provider_options || {}; end
      def configured_model_options; @model_options || {}; end
      def configured_with_use_model?; @configured_with_use_model == true; end
    end

    def initialize(provider_override: nil, model_override: nil, options_override: {})
      target_provider_name = provider_override || self.class.configured_provider_name || OmniAgent.configuration.default_provider
      target_model = model_override || self.class.configured_provider_options[:model]
      @chat_options = self.class.configured_model_options.merge(options_override)
      @provider = resolve_provider(target_provider_name, target_model)
    end

    def run(input, context: {})
      messages = [
        { role: "system", content: system_prompt(context: context) },
        { role: "user", content: input }
      ]

      loop do
        response = provider.chat(messages: messages, tools: available_tools, **@chat_options)

        if response.content && !response.tool_calls?
          messages << { role: "assistant", content: response.content }
          return response.content
        end

        messages << {
          role: "assistant",
          content: response.content,
          tool_calls: response.raw_response.dig("choices", 0, "message", "tool_calls")
        }

        response.tool_calls.each do |tool_call|
          tool_name = tool_call[:name]
          tool_args = tool_call[:arguments]
          tool_id   = tool_call[:id]

          tool_class = available_tools.find { |t| t.name.demodulize == tool_name }

          if tool_class
            begin
              result = tool_class.invoke(tool_args)

              messages << {
                role: "tool",
                tool_call_id: tool_id,
                name: tool_name,
                content: result.to_s
              }
            rescue => e
              messages << {
                role: "tool",
                tool_call_id: tool_id,
                name: tool_name,
                content: "Error executing tool: #{e.message}"
              }
            end
          else
            messages << {
              role: "tool",
              tool_call_id: tool_id,
              name: tool_name,
              content: "Error: Tool #{tool_name} is not registered to this agent."
            }
          end
        end
      end
    end

    def available_tools
      tool_namespace = "#{self.class.name}::Tools".safe_constantize
      return [] unless tool_namespace

      tool_namespace.constants.filter_map do |const_name|
        const = tool_namespace.const_get(const_name)
        const if const.is_a?(Class) && const < OmniAgent::Tool
      end
    end

    private

    def resolve_provider(name, model)
      OmniAgent::Providers.registry[name.to_sym].new(model: model)
    end

    def system_prompt(context:)
      return "You are a helpful assistant with access to local tools." unless defined?(Rails)

      class_name = self.class.name
      return "You are a helpful assistant with access to local tools." if class_name.nil?

      file_path = Rails.root.join("app", "agents", class_name.underscore, "prompt.md.erb")
      ERB.new(File.read(file_path)).result_with_hash(context)
    end
  end
end