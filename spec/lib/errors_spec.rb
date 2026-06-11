require_relative "../spec_helper"
require_relative "../../lib/omni_agent/errors"

RSpec.describe OmniAgent::Error do
  it "inherits from StandardError" do
    expect(described_class).to be < StandardError
  end
end

RSpec.describe OmniAgent::MissingDependencyError do
  it "inherits from OmniAgent::Error" do
    expect(described_class).to be < OmniAgent::Error
  end
end

RSpec.describe OmniAgent::Errors do
  it "defines the expected error classes" do
    expect(OmniAgent::Errors::Error).to eq(OmniAgent::Error)
    expect(OmniAgent::Errors::MissingDependencyError).to eq(OmniAgent::MissingDependencyError)
  end
end
