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
