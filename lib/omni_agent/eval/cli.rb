module OmniAgent
  class Eval
    module CLI
      DEFAULT_PATTERN = "evals/**/*_eval.rb"

      def self.run(pattern: nil, fresh: false)
        OmniAgent::Eval::Cache.clear! if fresh

        files = Dir.glob(Rails.root.join(pattern || DEFAULT_PATTERN))
        return :no_files if files.empty?

        files.each { |file| require file }

        eval_classes = ObjectSpace.each_object(Class).select { |klass| klass < OmniAgent::Eval }
        return :no_evals if eval_classes.empty?

        reports = eval_classes.map(&:run_all)
        reports.each(&:print)

        reports.all?(&:passed?) ? :passed : :failed
      end
    end
  end
end
