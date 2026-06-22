namespace :omni_agent do
  desc 'Run evals. Usage: rake omni_agent:eval or rake "omni_agent:eval[evals/research_agent_eval.rb,fresh]". Pass `fresh` as the 2nd arg, or set FRESH=1, to bypass the eval cache.'
  task :eval, [ :pattern, :fresh ] => :environment do |_task, args|
    fresh = ENV["FRESH"] == "1" || args[:fresh] == "fresh"
    pattern = args[:pattern].to_s.strip
    pattern = nil if pattern.empty?

    status = OmniAgent::Eval::CLI.run(pattern: pattern, fresh: fresh)

    case status
    when :no_files
      abort "No eval files found matching #{(pattern || OmniAgent::Eval::CLI::DEFAULT_PATTERN).inspect}"
    when :no_evals
      abort "No OmniAgent::Eval subclasses found"
    when :failed
      exit 1
    end
  end
end
