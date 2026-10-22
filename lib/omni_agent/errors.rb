module OmniAgent
  module Errors
    class Error < StandardError; end
    class MissingDependencyError < Error; end
    class UnknownProviderError < Error; end
    class MaxToolIterationsError < Error; end
    class MaxDelegationDepthError < Error; end
    class EvalAssertionError < Error; end
    class MCPError < Error; end
    class StructuredOutputError < Error; end
    class UnknownStockAgentError < Error; end
  end

  Error = Errors::Error
  MissingDependencyError = Errors::MissingDependencyError
  UnknownProviderError = Errors::UnknownProviderError
  MaxToolIterationsError = Errors::MaxToolIterationsError
  MaxDelegationDepthError = Errors::MaxDelegationDepthError
  EvalAssertionError = Errors::EvalAssertionError
  MCPError = Errors::MCPError
  StructuredOutputError = Errors::StructuredOutputError
  UnknownStockAgentError = Errors::UnknownStockAgentError
end
