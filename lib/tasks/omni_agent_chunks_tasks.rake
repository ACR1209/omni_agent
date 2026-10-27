namespace :omni_agent do
  namespace :chunks do
    desc 'Chunk and embed records that have no chunks. Usage: rake "omni_agent:chunks:ingest[Document]", add ",force" to re-ingest every record'
    task :ingest, [ :model, :force ] => :environment do |_task, args|
      model_name = args[:model].to_s.strip
      abort 'Please provide a model. Example: bin/rails "omni_agent:chunks:ingest[Document]"' if model_name.empty?

      model = model_name.safe_constantize
      abort "#{model_name} does not use has_chunks" unless model.respond_to?(:ingest_all)

      skipped = model.ingest_all(force: args[:force] == "force")
      skipped.each { |id, message| puts "Skipped #{model_name}##{id}: #{message}" }
      puts "Ingested #{model_name} records."
    end
  end
end
