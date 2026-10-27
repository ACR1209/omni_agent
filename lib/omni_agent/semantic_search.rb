module OmniAgent
  # Runs a semantic search on anything `Agent.searches` accepts: a model or
  # relation with `has_embedding` (or its own `semantic_search(query, limit:)`),
  # or a meilisearch-rails model, searched with one of its index embedders.
  module SemanticSearch
    def self.searchable?(target)
      target.respond_to?(:semantic_search) || meilisearch?(target)
    end

    def self.call(target, query, limit:, embedder: "default")
      return target.semantic_search(query, limit: limit) if target.respond_to?(:semantic_search)
      return meilisearch(target.all, query, limit: limit, embedder: embedder) if meilisearch?(target)

      raise ArgumentError, "#{target.inspect} can't be searched"
    end

    def self.meilisearch?(target)
      model = target.is_a?(Class) ? target : target.try(:klass)
      defined?(::Meilisearch::Rails) && model.is_a?(Class) && model < ::Meilisearch::Rails
    end

    # Equality conditions of the relation become Meilisearch filters (those
    # attributes must be filterable_attributes). Hits are then checked
    # against the full relation, so no condition is ever silently skipped.
    def self.meilisearch(relation, query, limit:, embedder:)
      params = { limit: limit, hybrid: { embedder: embedder } }
      filter = relation.where_values_hash.map { |attribute, value| meilisearch_condition(attribute, value) }
      params[:filter] = filter if filter.any?

      hits = relation.klass.ms_search(query, params).first(limit)
      allowed = relation.where(relation.klass.primary_key => hits.map(&:id)).pluck(relation.klass.primary_key).to_set
      hits.select { |hit| allowed.include?(hit.id) }
    end

    def self.meilisearch_condition(attribute, value)
      case value
      when nil then "#{attribute} IS NULL"
      when Array then "#{attribute} IN [#{value.map(&:to_json).join(', ')}]"
      else "#{attribute} = #{value.to_json}"
      end
    end

    private_class_method :meilisearch, :meilisearch_condition
  end
end
