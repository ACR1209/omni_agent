namespace :omni_agent do
  desc 'Run an MCP server over stdio. Usage: rake "omni_agent:mcp[SupportServer]"'
  task :mcp, [ :server ] => :environment do |_task, args|
    server = args[:server].to_s.strip
    abort 'Please provide a server class. Example: bin/rails "omni_agent:mcp[SupportServer]"' if server.empty?

    OmniAgent::MCP::Stdio.start(server)
  end
end
