require_relative "../spec_helper"
require_relative "../../lib/errors"

RSpec.describe OmniAgents::Error do
  it "inherits from StandardError" do
    expect(described_class).to be < StandardError
  end
end

RSpec.describe OmniAgents::MissingDependencyError do
  it "inherits from OmniAgents::Error" do
    expect(described_class).to be < OmniAgents::Error
  end
end
