module OmniAgent
  module StockAgents
    # Classifies the input into the labels the host app declares, with a
    # confidence score and a short reason:
    #
    #   class TicketTriage < OmniAgent::StockAgents::Classifier
    #     labels billing: "Payments, invoices, refunds", bug: "Something is broken"
    #   end
    #
    #   TicketTriage.new.run("I was charged twice").structured_output
    #   # => { label: "billing", confidence: 0.93, reason: "Mentions a duplicate charge" }
    #
    # `labels ..., multiple: true` returns a `labels` array instead, empty when
    # none apply. Without `labels`, the model names a short label itself.
    class Classifier < OmniAgent::StockAgent
      description "Classifies input into one or more of your labels"
      use_model "gpt-4o-mini"

      CONFIDENCE = "How sure you are of the classification, from 0 to 1".freeze
      REASON = "One short sentence on what in the input decided the classification".freeze

      # Default structured output. Declaring `labels` (or your own
      # `output do ... end` block) in a subclass replaces it.
      output do
        string :label, description: "Short, lowercase label for the input"
        number :confidence, min: 0, max: 1, description: CONFIDENCE
        string :reason, description: REASON
      end

      class << self
        # Declares the labels to pick from, with optional descriptions that are
        # rendered into the prompt, and rebuilds the output schema around them:
        #
        #   labels :billing, :bug
        #   labels billing: "Payments, invoices, refunds", bug: "Something is broken"
        #   labels :spam, :toxic, multiple: true
        #
        # Without arguments, returns the declared labels as { "name" => description }.
        def labels(*names, multiple: nil, **described)
          if names.empty? && described.empty? && multiple.nil?
            return @labels || (superclass.respond_to?(:labels) ? superclass.labels : {})
          end

          @labels = normalize_labels(names, described)
          @multiple_labels = multiple == true
          define_label_output(@labels.keys, @multiple_labels)
        end

        def multiple_labels?
          return @multiple_labels unless @multiple_labels.nil?

          superclass.respond_to?(:multiple_labels?) && superclass.multiple_labels?
        end

        private

        def normalize_labels(names, described)
          entries = names.map { |name| [ name, nil ] } + described.to_a
          raise ArgumentError, "labels requires at least one label" if entries.empty?

          entries.each_with_object({}) do |(name, label_description), normalized|
            raise ArgumentError, "label names must be strings or symbols, got #{name.inspect}" unless name.is_a?(String) || name.is_a?(Symbol)
            raise ArgumentError, "duplicate label #{name.to_s.inspect}" if normalized.key?(name.to_s)

            normalized[name.to_s] = label_description&.to_s
          end
        end

        def define_label_output(values, multiple)
          output do
            if multiple
              array :labels, values: values, description: "Every label that applies to the input; empty when none apply"
            else
              enum :label, values: values, description: "The label that fits the input best"
            end
            number :confidence, min: 0, max: 1, description: CONFIDENCE
            string :reason, description: REASON
          end
        end
      end

      private

      # The prompt renders in an isolated scope, so pass it the class-level
      # labels on a copy of the context.
      def system_prompt(context:, prompt_method: nil)
        prompt_context = context.merge(classifier_labels: self.class.labels, classifier_multiple: self.class.multiple_labels?)

        super(context: prompt_context, prompt_method: prompt_method)
      end
    end
  end
end
