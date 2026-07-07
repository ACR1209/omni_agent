module OmniAgent
  class Agent
    attr_reader :provider

    module ImplicitRunEntrypoints
      def method_added(method_name)
        super

        return if @_omni_agent_wrapping_method
        return if method_name.to_s.start_with?("__omni_agent_original_")
        return unless instance_methods(false).include?(method_name)
        return if OmniAgent::Agent.instance_methods(false).include?(method_name)

        original_method = instance_method(method_name)
        return unless original_method.arity == 0

        alias_name = "__omni_agent_original_#{method_name}".to_sym
        return if instance_methods(false).include?(alias_name)

        @_omni_agent_wrapping_method = true
        alias_method alias_name, method_name

        define_method(method_name) do |input = nil, context: {}, **context_keywords|
          if input.nil? && context == {} && context_keywords.empty?
            run_alias_entrypoint_logic(alias_name)
          else
            merged_context = context.is_a?(Hash) ? context.dup : {}
            merged_context.merge!(context_keywords)

            run_input = run_alias_entrypoint_logic(alias_name, fallback_input: input)

            run(run_input, context: merged_context, prompt_method: method_name)
          end
        end
      ensure
        @_omni_agent_wrapping_method = false
      end
    end

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

      def before_generation(*callbacks)
        @before_generation_callbacks = configured_before_generation_callbacks + normalize_callbacks(:before_generation, callbacks)
      end

      def after_generation(*callbacks)
        @after_generation_callbacks = configured_after_generation_callbacks + normalize_callbacks(:after_generation, callbacks)
      end

      def tags(*tag_names)
        return @configured_tags || [] if tag_names.empty?

        @configured_tags = (tags + normalize_tags(tag_names)).uniq
      end

      def run_aliases(*method_names)
        aliases = normalize_callbacks(:run_aliases, method_names)

        aliases.each do |method_name|
          define_method(method_name) do |input, context: {}|
            run(input, context: context, prompt_method: method_name)
          end
        end
      end

      def delegate_to(agent_class, as:, description: nil, run_alias: nil, forward: [])
        unless agent_class.is_a?(Class) && agent_class <= OmniAgent::Agent
          raise ArgumentError, "delegate_to requires an OmniAgent::Agent subclass"
        end

        tool_class = build_delegated_tool_class(agent_class, description: description, run_alias: run_alias, forward: forward)
        delegated_tools_module.const_set(delegated_tool_const_name(as), tool_class)

        @delegated_tool_classes = configured_delegated_tool_classes + [ tool_class ]
      end

      def configured_delegated_tool_classes
        @delegated_tool_classes || []
      end

      def with(context = nil, provider_override: nil, model_override: nil, options_override: {}, **context_keywords)
        merged_context = {}
        merged_context.merge!(context) if context.is_a?(Hash)
        merged_context.merge!(context_keywords)

        new(
          provider_override: provider_override,
          model_override: model_override,
          options_override: options_override,
          context_override: merged_context
        )
      end

      def configured_provider_name; @provider_name; end
      def configured_provider_options; @provider_options || {}; end
      def configured_model_options; @model_options || {}; end
      def configured_with_use_model?; @configured_with_use_model == true; end
      def configured_before_generation_callbacks; @before_generation_callbacks || []; end
      def configured_after_generation_callbacks; @after_generation_callbacks || []; end
      def configured_tags; tags; end

      def inherited(subclass)
        super
        subclass.extend(ImplicitRunEntrypoints)
      end

      private

      def delegated_tools_module
        @delegated_tools_module ||= const_set(:DelegatedTools, Module.new)
      end

      def delegated_tool_const_name(as)
        as.to_s.split(/[_\s]+/).reject(&:empty?).map { |part| part[0].upcase + part[1..] }.join
      end

      def build_delegated_tool_class(agent_class, description:, run_alias:, forward:)
        tool_description = description || "Delegate to #{agent_class.name}."

        Class.new(OmniAgent::Tool) do
          description tool_description

          input do
            string :input, description: "Input/question to send to the delegated agent."
          end

          define_method(:execute) do |input:|
            forwarded_context = OmniAgent::Agent.__send__(:filter_forwarded_context, context, forward)
            OmniAgent::Agent.__send__(:run_delegated_agent, agent_class, input, run_alias, forwarded_context)
          end
        end
      end

      def filter_forwarded_context(context, forward)
        return {} unless context.is_a?(Hash)
        return context.dup if forward == true
        return {} if forward.nil? || forward == false

        keys = Array(forward).map(&:to_sym)
        context.select { |key, _| keys.include?(key.to_sym) }
      end

      def run_delegated_agent(agent_class, input, run_alias, forwarded_context)
        depth = (Thread.current[:omni_agent_delegation_depth] ||= 0)
        max_depth = OmniAgent.configuration.max_delegation_depth

        if depth >= max_depth
          raise OmniAgent::MaxDelegationDepthError,
                "Exceeded max_delegation_depth (#{max_depth}) while delegating to #{agent_class.name}."
        end

        Thread.current[:omni_agent_delegation_depth] = depth + 1
        begin
          entrypoint = run_alias || :run
          agent_class.new.public_send(entrypoint, input, context: forwarded_context).answer
        ensure
          Thread.current[:omni_agent_delegation_depth] = depth
        end
      end

      def normalize_callbacks(callback_type, callbacks)
        raise ArgumentError, "#{callback_type} requires at least one method name" if callbacks.empty?

        callbacks.map do |callback|
          unless callback.is_a?(String) || callback.is_a?(Symbol)
            raise ArgumentError, "#{callback_type} callbacks must be method names"
          end

          callback.to_sym
        end
      end

      def normalize_tags(tag_names)
        raise ArgumentError, "tags requires at least one tag" if tag_names.empty?

        tag_names.map do |tag_name|
          unless tag_name.is_a?(String) || tag_name.is_a?(Symbol)
            raise ArgumentError, "tags must be strings or symbols"
          end

          tag_name.to_sym
        end
      end
    end

    def initialize(provider_override: nil, model_override: nil, options_override: {}, context_override: {})
      target_provider_name = provider_override || self.class.configured_provider_name || OmniAgent.configuration.default_provider
      target_model = model_override || self.class.configured_provider_options[:model]
      @chat_options = self.class.configured_model_options.merge(options_override)
      @provider = resolve_provider(target_provider_name, target_model)
      @default_context = context_override || {}
    end

    def run(input, context: {}, prompt_method: nil)
      context = @default_context.merge(context || {})
      bind_context_instance_variables(context)

      messages = []

      run_before_generation_callbacks(input: input, context: context, messages: messages)
      sync_context_from_instance_variables(context)

      messages.replace(build_messages(input: input, history: context[:history]))
      messages[0][:content] = system_prompt(context: context, prompt_method: prompt_method)
      initial_messages_count = messages.length - 1

      filtered_tools = tool_filter(tools: available_tools, agent_tags: self.class.tags)
      max_iterations = OmniAgent.configuration.max_tool_iterations
      iterations = 0

      loop do
        iterations += 1
        if iterations > max_iterations
          raise OmniAgent::MaxToolIterationsError,
                "Exceeded max_tool_iterations (#{max_iterations}) without a final response. " \
                "Increase OmniAgent.configuration.max_tool_iterations if more tool calls are expected."
        end

        response = provider.chat(messages: messages, tools: filtered_tools, **@chat_options)

        if response.content && !response.tool_calls?
          messages << { role: "assistant", content: response.content }
          set_after_generation_state(response: response, messages: messages, initial_messages_count: initial_messages_count)
          run_after_generation_callbacks(input: input, context: context, messages: messages, response: response)
          sync_context_from_instance_variables(context)
          return response
        end

        messages << build_assistant_tool_call_message(response)
        should_stop_generation = false

        response.tool_calls.each do |tool_call|
          tool_name = tool_call[:name]
          tool_args = tool_call[:arguments]
          tool_id   = tool_call[:id]

          tool_class = filtered_tools.find do |t|
            class_name = t.name.to_s
            simple_name = class_name.respond_to?(:demodulize) ? class_name.demodulize : class_name.split("::").last
            simple_name == tool_name
          end

          if tool_class
            tool_instance = tool_class.new
            tool_instance.context = context if tool_instance.respond_to?(:context=)

            begin
              result = tool_instance.invoke(tool_args)

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

            should_stop_generation ||= tool_class.respond_to?(:stops_generation?) && tool_class.stops_generation?
            should_stop_generation ||= tool_instance.respond_to?(:stops_generation?) && tool_instance.stops_generation?
          else
            messages << {
              role: "tool",
              tool_call_id: tool_id,
              name: tool_name,
              content: "Error: Tool #{tool_name} is not registered to this agent."
            }
          end
        end

        if should_stop_generation
          set_after_generation_state(response: response, messages: messages, initial_messages_count: initial_messages_count)
          run_after_generation_callbacks(input: input, context: context, messages: messages, response: response)
          sync_context_from_instance_variables(context)
          return response
        end
      end
    end

    def available_tools
      tool_namespace = "#{self.class.name}::Tools".safe_constantize

      namespace_tools = if tool_namespace
        tool_namespace.constants.filter_map do |const_name|
          const = tool_namespace.const_get(const_name)
          const if const.is_a?(Class) && const < OmniAgent::Tool
        end
      else
        []
      end

      namespace_tools + self.class.configured_delegated_tool_classes
    end

    private

    def tool_filter(tools:, agent_tags:)
      tools
    end

    def build_messages(input:, history:)
      normalized_history = normalize_history_messages(history)

      [
        { role: "system", content: nil },
        *normalized_history,
        { role: "user", content: input }
      ]
    end

    def normalize_history_messages(history)
      return [] if history.nil?
      return [] unless history.is_a?(Array)

      history.filter_map do |message|
        next unless message.is_a?(Hash)

        normalized = message.transform_keys(&:to_sym)
        normalized.compact
      end
    end

    def build_assistant_tool_call_message(response)
      message = { role: "assistant" }
      message[:content] = response.content unless response.content.nil?

      raw_tool_calls = response.raw_response.is_a?(Hash) ? response.raw_response.dig("choices", 0, "message", "tool_calls") : nil
      normalized_tool_calls = normalize_tool_calls_for_message(raw_tool_calls, response.tool_calls)
      message[:tool_calls] = normalized_tool_calls unless normalized_tool_calls.empty?

      message
    end

    def normalize_tool_calls_for_message(raw_tool_calls, parsed_tool_calls)
      return raw_tool_calls if raw_tool_calls.is_a?(Array) && !raw_tool_calls.empty?

      Array(parsed_tool_calls).map do |tool_call|
        {
          "id" => tool_call[:id],
          "type" => "function",
          "function" => {
            "name" => tool_call[:name],
            "arguments" => serialize_tool_arguments(tool_call[:arguments])
          }
        }
      end
    end

    def serialize_tool_arguments(arguments)
      return arguments if arguments.is_a?(String)
      return JSON.generate(arguments) if defined?(JSON)

      arguments.to_s
    end

    def run_alias_entrypoint_logic(alias_name, fallback_input: nil)
      @message = nil
      result = public_send(alias_name)
      computed_message = result.nil? ? @message : result

      return computed_message if fallback_input.nil?

      fallback_input
    end

    def resolve_provider(name, model)
      provider_class = OmniAgent::Providers.registry[name.to_sym]

      unless provider_class
        known = OmniAgent::Providers.registry.keys.join(", ")
        raise OmniAgent::UnknownProviderError,
              "Unknown provider #{name.inspect}. Known providers: #{known}"
      end

      provider_class.new(model: model)
    end

    def run_before_generation_callbacks(input:, context:, messages:)
      payload = { input: input, context: context, messages: messages }

      self.class.configured_before_generation_callbacks.each do |callback_name|
        invoke_generation_callback(callback_name, payload)
      end
    end

    def run_after_generation_callbacks(input:, context:, messages:, response:)
      payload = {
        input: input,
        context: context,
        messages: messages,
        generated_messages: response.generated_messages,
        response: response
      }

      self.class.configured_after_generation_callbacks.each do |callback_name|
        invoke_generation_callback(callback_name, payload)
      end
    end

    def set_after_generation_state(response:, messages:, initial_messages_count:)
      generated_messages = messages.drop(initial_messages_count)
      @response = response.with_generated_messages(generated_messages)
    end

    def invoke_generation_callback(callback_name, payload)
      original_callback_name = "__omni_agent_original_#{callback_name}".to_sym
      callback_target = if respond_to?(original_callback_name, true)
        original_callback_name
      else
        callback_name
      end

      callback_method = self.class.instance_method(callback_target)
      bind_context_instance_variables(payload[:context])

      if callback_method.arity == 0
        __send__(callback_target)
      else
        __send__(callback_target, payload)
      end

      sync_context_from_instance_variables(payload[:context])
    end

    def bind_context_instance_variables(context)
      return unless context.is_a?(Hash)

      @__omni_agent_context_bindings ||= {}

      context.each do |key, value|
        ivar_name = "@#{key}"
        next unless ivar_name.match?(/\A@[a-zA-Z_]\w*\z/)

        ivar = ivar_name.to_sym
        instance_variable_set(ivar, value)
        @__omni_agent_context_bindings[ivar] = key
      end
    end

    def sync_context_from_instance_variables(context)
      return unless context.is_a?(Hash)

      if instance_variable_defined?(:@__omni_agent_context_bindings)
        @__omni_agent_context_bindings.each do |ivar, key|
          next unless instance_variable_defined?(ivar)
          context[key] = instance_variable_get(ivar)
        end
      end

      if instance_variable_defined?(:@history)
        context[:history] = @history
      end
    end

    def system_prompt(context:, prompt_method: nil)
      return "You are a helpful assistant with access to local tools." unless defined?(Rails)

      class_name = self.class.name
      return "You are a helpful assistant with access to local tools." if class_name.nil?

      agent_dir = inflector_underscore(class_name)
      base_file_path = Rails.root.join("app", "agents", agent_dir, "prompt.md.erb")
      method_file_path = if prompt_method
        prompt_method_name = inflector_underscore(prompt_method.to_s)
        Rails.root.join("app", "agents", agent_dir, "#{prompt_method_name}.md.erb")
      end

      isolated_scope = Object.new

      context.each do |key, value|
        isolated_scope.instance_variable_set("@#{key}", value)
      end

      internal_vars = [ :@provider, :@chat_options ] # Blacklists internal instance variables

      (instance_variables - internal_vars).each do |ivar|
        isolated_scope.instance_variable_set(ivar, instance_variable_get(ivar))
      end

      base_prompt = render_prompt_template(base_file_path, isolated_scope)
      method_prompt = render_prompt_template(method_file_path, isolated_scope)

      prompts = [ base_prompt, method_prompt ].compact.reject(&:empty?)
      return prompts.join("\n\n") if prompts.any?

      "You are a helpful assistant with access to local tools."
    end

    def render_prompt_template(file_path, isolated_scope)
      return nil unless file_path && File.exist?(file_path)

      ERB.new(File.read(file_path)).result(isolated_scope.instance_eval { binding })
    end

    def inflector_underscore(text)
      return text.underscore if text.respond_to?(:underscore)

      text
        .to_s
        .gsub("::", "/")
        .gsub(/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
        .gsub(/([a-z\d])([A-Z])/, "\\1_\\2")
        .tr("-", "_")
        .downcase
    end
  end
end
