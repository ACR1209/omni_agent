require "digest"
require "fileutils"
require "json"

module OmniAgent
  class Eval
    module Cache
      def self.fetch(key)
        return yield unless OmniAgent.configuration.eval_cache_enabled

        store = read_store
        return store[key] if store.key?(key)

        result = yield
        store[key] = result
        write_store(store)
        result
      end

      def self.key_for(agent_class:, run_alias:, input:, context:)
        Digest::SHA256.hexdigest(JSON.generate(
          agent: agent_class.name,
          run_alias: run_alias,
          input: input,
          context: context
        ))
      end

      def self.clear!
        File.delete(path) if File.exist?(path)
      end

      def self.path
        OmniAgent.configuration.eval_cache_path
      end

      def self.read_store
        return {} unless File.exist?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        {}
      end

      def self.write_store(store)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.generate(store))
      end
    end
  end
end
