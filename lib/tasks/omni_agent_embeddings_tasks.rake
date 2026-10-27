namespace :omni_agent do
  namespace :embeddings do
    desc 'Embed records missing a vector. Usage: rake "omni_agent:embeddings:backfill[Document]", add ",force" to re-embed every record'
    task :backfill, [ :model, :force ] => :environment do |_task, args|
      model_name = args[:model].to_s.strip
      abort 'Please provide a model. Example: bin/rails "omni_agent:embeddings:backfill[Document]"' if model_name.empty?

      model = model_name.safe_constantize
      abort "#{model_name} does not use has_embedding" unless model.respond_to?(:embed_all)

      model.embed_all(force: args[:force] == "force")
      puts "Embedded #{model_name} records."
    end
  end
end
