module OmniAgent
  module Errors
    class Error < StandardError; end
    class MissingDependencyError < Error; end
    class UnknownProviderError < Error; end
    class MaxToolIterationsError < Error; end
    class EvalAssertionError < Error; end
  end

  Error = Errors::Error
  MissingDependencyError = Errors::MissingDependencyError
  UnknownProviderError = Errors::UnknownProviderError
  MaxToolIterationsError = Errors::MaxToolIterationsError
  EvalAssertionError = Errors::EvalAssertionError
end
