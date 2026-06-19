module OmniAgent
  module Errors
    class Error < StandardError; end
    class MissingDependencyError < Error; end
    class UnknownProviderError < Error; end
  end

  Error = Errors::Error
  MissingDependencyError = Errors::MissingDependencyError
  UnknownProviderError = Errors::UnknownProviderError
end
