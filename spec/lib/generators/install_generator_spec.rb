require_relative "../../rails_helper"
require "rails/generators"
require "generators/omni_agent/install/install_generator"

RSpec.describe OmniAgent::Generators::InstallGenerator do
  around do |example|
    Dir.mktmpdir do |dir|
      @destination = dir
      example.run
    end
  end

  def generate
    original_stdout = $stdout
    $stdout = StringIO.new
    described_class.start([], destination_root: @destination)
  ensure
    $stdout = original_stdout
  end

  def initializer_path
    File.join(@destination, "config", "initializers", "omni_agent.rb")
  end

  it "writes an initializer listing every setting with its default" do
    generate
    initializer = File.read(initializer_path)

    expect(initializer).to start_with("OmniAgent.configure do |config|")
    setters = initializer.scan(/# config\.(\w+) =/).flatten
    expect(setters).to match_array(OmniAgent::Configuration.public_instance_methods(false).grep(/=\z/).map { |name| name.to_s.delete_suffix("=") })
  end

  it "keeps an existing initializer" do
    FileUtils.mkdir_p(File.dirname(initializer_path))
    File.write(initializer_path, "# mine\n")

    generate

    expect(File.read(initializer_path)).to eq("# mine\n")
  end
end
