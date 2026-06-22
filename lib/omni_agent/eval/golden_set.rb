require "yaml"
require "json"

module OmniAgent
  class Eval
    module GoldenSet
      def self.load(path)
        rows = path.to_s.end_with?(".json") ? JSON.parse(File.read(path)) : YAML.safe_load_file(path)
        Array(rows).map { |row| deep_symbolize(row) }
      end

      def self.deep_symbolize(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, val), memo| memo[key.to_sym] = deep_symbolize(val) }
        when Array
          value.map { |item| deep_symbolize(item) }
        else
          value
        end
      end
    end
  end
end
