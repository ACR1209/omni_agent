require "rails/generators/named_base"
require "fileutils"

module OmniAgent
  module Generators
    class EvalGenerator < Rails::Generators::NamedBase
      def create_eval_file
        FileUtils.mkdir_p(evals_directory)

        create_file(eval_file_path, <<~RUBY)
          class #{eval_class_name} < OmniAgent::Eval
            agent #{class_name}

            eval_case "describe what #{class_name} should do" do
              input "Say hello"
              expect_output to_include: "hello"
            end
          end
        RUBY
      end

      private

      def evals_directory
        File.join(destination_root, "evals")
      end

      def eval_file_path
        File.join(evals_directory, "#{file_name}_eval.rb")
      end

      def eval_class_name
        "#{class_name}Eval"
      end
    end
  end
end
