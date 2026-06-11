module OmniAgent
  module Errors
    class Error < StandardError; end
    class MissingDependencyError < Error; end
  end

  Error = Errors::Error
  MissingDependencyError = Errors::MissingDependencyError
end
