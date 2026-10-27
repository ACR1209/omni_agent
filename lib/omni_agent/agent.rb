require "json"

module OmniAgent
  class Agent
    DEFAULT_SYSTEM_PROMPT = "You are a helpful assistant with access to local tools.".freeze

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

        define_method(method_name) do |input = nil, context: {}, **context_keywords, &block|
          if input.nil? && context == {} && context_keywords.empty?
            run_alias_entrypoint_logic(alias_name)
          else
            merged_context = context.is_a?(Hash) ? context.dup : {}
            merged_context.merge!(context_keywords)

            run_input = run_alias_entrypoint_logic(alias_name, fallback_input: input)

            run(run_input, context: merged_context, prompt_method: method_name, &block)
          end
        end
      ensure
        @_omni_agent_wrapping_method = false
      end
    end

    class << self
      def provider(name, **options)
        if @configured_with_use_model == true
          raise OmniAgent::Error, "Cannot combine `provider` and `use_model` in the same agent. Use either `provider ..., model: ...` or `use_model ...`."
        end

        @provider_name = name
        @provider_options = options
      end

      def options(**options)
        @model_options = configured_model_options.merge(options)
      end

      def use_model(name)
        if @provider_name || (@provider_options || {}).any?
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
        return @configured_tags || inherited_setting(:tags) || [] if tag_names.empty?

        @configured_tags = (tags + normalize_tags(tag_names)).uniq
      end

      # Declares the structured output the agent must produce, using the same
      # DSL as Tool.input. The final response is parsed and validated against
      # it and exposed as response.structured_output.
      def output(&block)
        @output_schema = OmniAgent::Schema.build(&block) if block_given?
      end

      def output_schema
        @output_schema || inherited_setting(:output_schema)
      end

      def run_aliases(*method_names)
        aliases = normalize_callbacks(:run_aliases, method_names)

        aliases.each do |method_name|
          define_method(method_name) do |input, context: {}, &block|
            run(input, context: context, prompt_method: method_name, &block)
          end
        end
      end

      def delegate_to(agent_class, as:, description: nil, run_alias: nil, forward: [])
        unless agent_class.is_a?(Class) && agent_class <= OmniAgent::Agent
          raise ArgumentError, "delegate_to requires an OmniAgent::Agent subclass"
        end

        tool_class = build_delegated_tool_class(agent_class, description: description, run_alias: run_alias, forward: forward)
        add_built_tool(as, tool_class)
      end

      # Gives the agent a Search<Models> tool backed by `target`: a model with
      # `has_embedding`, a meilisearch-rails model, or anything responding to
      # `semantic_search(query, limit:)`. `scope` runs on the target with the
      # run context, e.g. ->(context) { where(account_id: context[:account_id]) }.
      def searches(target, as: nil, description: nil, scope: nil, limit: 5, embedder: "default")
        unless OmniAgent::SemanticSearch.searchable?(target)
          raise ArgumentError,
                "#{target.name || target.inspect} can't be searched: add `has_embedding` to it, " \
                "include Meilisearch::Rails, or define `self.semantic_search(query, limit:)`."
        end

        plural = target.name.to_s.split("::").last.underscore.pluralize
        tool_description = description || "Search #{plural.humanize(capitalize: false)} by meaning. Returns the closest matches with their ids."

        tool_class = Class.new(OmniAgent::Tool) do
          description tool_description
          annotations read_only: true

          input do
            string :query, description: "What to look for, in natural language."
          end

          define_method(:execute) do |query:|
            searched = scope ? target.instance_exec(context, &scope) : target
            results = OmniAgent::SemanticSearch.call(searched, query, limit: limit, embedder: embedder)
            next "No results." if results.empty?

            results.map { |result| OmniAgent::Agent.__send__(:format_search_result, result, target) }.join("\n\n---\n\n")
          end
        end

        add_built_tool(as || "search_#{plural}", tool_class)
      end

      def configured_delegated_tool_classes
        @delegated_tool_classes || inherited_setting(:configured_delegated_tool_classes) || []
      end

      def tool_classes
        tool_namespace = "#{name}::Tools".safe_constantize

        namespace_tools = if tool_namespace
          tool_namespace.constants.filter_map do |const_name|
            const = tool_namespace.const_get(const_name)
            const if const.is_a?(Class) && const < OmniAgent::Tool
          end
        else
          []
        end

        # The model calls tools by simple name, so a subclass tool or a later
        # delegate_to with the same name replaces the inherited one.
        delegated_tools = configured_delegated_tool_classes.reverse.uniq { |tool| tool_call_name(tool) }.reverse
        (namespace_tools + delegated_tools + (inherited_setting(:tool_classes) || [])).uniq { |tool| tool_call_name(tool) }
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

      # Class-level settings fall back to the parent agent, so subclasses
      # (e.g. of a stock agent) keep its provider, options, callbacks and tools.
      # A class's own `use_model` means "default provider + this model", so it
      # does not inherit the parent's provider name.
      def configured_provider_name
        return @provider_name if @provider_name
        return nil if @configured_with_use_model == true

        inherited_setting(:configured_provider_name)
      end

      def configured_provider_options; @provider_options || inherited_setting(:configured_provider_options) || {}; end
      def configured_model_options; @model_options || inherited_setting(:configured_model_options) || {}; end
      def configured_with_use_model?; @configured_with_use_model == true || inherited_setting(:configured_with_use_model?) == true; end
      def configured_before_generation_callbacks; @before_generation_callbacks || inherited_setting(:configured_before_generation_callbacks) || []; end
      def configured_after_generation_callbacks; @after_generation_callbacks || inherited_setting(:configured_after_generation_callbacks) || []; end
      def configured_tags; tags; end

      def inherited(subclass)
        super
        subclass.extend(ImplicitRunEntrypoints)
      end

      private

      def inherited_setting(reader)
        return nil unless superclass < OmniAgent::Agent

        superclass.public_send(reader)
      end

      def tool_call_name(tool)
        tool.name ? tool.name.split("::").last : tool
      end

      def add_built_tool(as, tool_class)
        delegated_tools_module.const_set(delegated_tool_const_name(as), tool_class)
        @delegated_tool_classes = configured_delegated_tool_classes + [ tool_class ]
      end

      def format_search_result(result, target)
        return target.format_search_chunk(result) if target.respond_to?(:format_search_chunk)
        return result.to_s unless result.respond_to?(:attributes)

        text = if result.respond_to?(:embedding_text)
          result.embedding_text
        else
          result.attributes.select { |_, value| value.is_a?(String) }.map { |key, value| "#{key}: #{value}" }.join("\n")
        end

        "[#{result.class.name}##{result.id}] #{text}"
      end

      def delegated_tools_module
        @delegated_tools_module ||= const_set(:DelegatedTools, Module.new)
      end

      def delegated_tool_const_name(as)
        as.to_s.split(/[_\s]+/).reject(&:empty?).map { |part| part[0].upcase + part[1..] }.join
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

    def stream
      OmniAgent::Streaming::Proxy.new(self)
    end

    def run(input, context: {}, prompt_method: nil, &stream)
      context = @default_context.merge(context || {})
      bind_context_instance_variables(context)

      messages = []

      run_before_generation_callbacks(input: input, context: context, messages: messages)
      sync_context_from_instance_variables(context)

      messages.replace(build_messages(input: input, history: context[:history]))
      output_schema = self.class.output_schema
      native_output = output_schema && provider_supports_structured_output?
      chat_options = native_output ? @chat_options.merge(output_schema: output_schema) : @chat_options

      messages[0][:content] = system_prompt(context: context, prompt_method: prompt_method)
      # Providers without native structured output (and non-strict schemas,
      # which the model only treats as guidance) also get the schema in the prompt.
      if output_schema && !(native_output && output_schema.strict_compatible?)
        messages[0][:content] = "#{messages[0][:content]}\n\n#{structured_output_instructions(output_schema)}"
      end
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

        response = provider.chat(messages: messages, tools: filtered_tools, stream: stream, **chat_options)

        if response.content && !response.tool_calls?
          messages << { role: "assistant", content: response.content }
          response.with_structured_output(parse_structured_output(response, output_schema)) if output_schema
          set_after_generation_state(response: response, messages: messages, initial_messages_count: initial_messages_count)
          run_after_generation_callbacks(input: input, context: context, messages: messages, response: response)
          sync_context_from_instance_variables(context)
          stream&.call(OmniAgent::Streaming::Event.done(response))
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

            stream&.call(OmniAgent::Streaming::Event.tool_call(name: tool_name, arguments: tool_args, id: tool_id))

            begin
              result = tool_instance.invoke(tool_args)

              messages << {
                role: "tool",
                tool_call_id: tool_id,
                name: tool_name,
                content: result.to_s
              }
              stream&.call(OmniAgent::Streaming::Event.tool_result(name: tool_name, id: tool_id, content: result.to_s))
            rescue => e
              error_content = "Error executing tool: #{e.message}"
              messages << {
                role: "tool",
                tool_call_id: tool_id,
                name: tool_name,
                content: error_content
              }
              stream&.call(OmniAgent::Streaming::Event.tool_result(name: tool_name, id: tool_id, content: error_content, error: true))
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
          stream&.call(OmniAgent::Streaming::Event.done(response))
          return response
        end
      end
    end

    def available_tools
      self.class.tool_classes
    end

    private

    def tool_filter(tools:, agent_tags:)
      tools
    end

    def provider_supports_structured_output?
      provider.respond_to?(:supports_structured_output?) && provider.supports_structured_output?
    end

    def structured_output_instructions(schema)
      "Respond only with a JSON object that matches this JSON schema, without any other text:\n" \
        "#{JSON.pretty_generate(schema.json_schema)}"
    end

    def parse_structured_output(response, schema)
      payload = JSON.parse(strip_json_code_fence(response.content.to_s), symbolize_names: true)
      schema.parse_typed(payload)
    rescue JSON::ParserError => e
      raise_structured_output_error("returned invalid JSON for its output schema: #{e.message}", response)
    rescue ArgumentError => e
      raise_structured_output_error("output does not match its output schema: #{e.message}", response)
    rescue StandardError => e
      # e.g. a polymorphic `resolve: true` field whose record can't be found
      raise_structured_output_error("output could not be resolved: #{e.class}: #{e.message}", response)
    end

    def raise_structured_output_error(reason, response)
      raise OmniAgent::StructuredOutputError.new(
        "#{self.class.name || 'Agent'} #{reason}",
        content: response.content,
        response: response
      )
    end

    # Models without native structured output sometimes wrap JSON in a fence.
    def strip_json_code_fence(content)
      match = content.strip.match(/\A```(?:json)?\s*(.*?)\s*```\z/m)
      match ? match[1] : content
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
      OmniAgent::Providers.fetch(name).new(model: model)
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
      template_paths = prompt_template_paths(prompt_method)
      return DEFAULT_SYSTEM_PROMPT if template_paths.empty?

      isolated_scope = Object.new

      context.each do |key, value|
        isolated_scope.instance_variable_set("@#{key}", value)
      end

      internal_vars = [ :@provider, :@chat_options ] # Blacklists internal instance variables

      (instance_variables - internal_vars).each do |ivar|
        isolated_scope.instance_variable_set(ivar, instance_variable_get(ivar))
      end

      prompts = template_paths.map { |path| render_prompt_template(path, isolated_scope) }.compact.reject(&:empty?)
      return prompts.join("\n\n") if prompts.any?

      DEFAULT_SYSTEM_PROMPT
    end

    # Ordered list of prompt templates to render; missing files are skipped.
    def prompt_template_paths(prompt_method)
      return [] unless defined?(Rails)

      class_name = self.class.name
      return [] if class_name.nil?

      prompt_templates_in(Rails.root.join("app", "agents", inflector_underscore(class_name)), prompt_method)
    end

    def prompt_templates_in(directory, prompt_method)
      paths = [ File.join(directory.to_s, "prompt.md.erb") ]
      paths << File.join(directory.to_s, "#{inflector_underscore(prompt_method.to_s)}.md.erb") if prompt_method
      paths
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
