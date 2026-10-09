require "rails_helper"
require "tmpdir"

RSpec.describe OmniAgent::MCP::Routing do
  def draw(&block)
    route_set = ActionDispatch::Routing::RouteSet.new
    route_set.draw(&block)
    route_set.routes.map do |route|
      { path: route.path.spec.to_s, name: route.name, server: route.app.app.server }
    end
  end

  describe "#mcp_server" do
    it "mounts <Name>Server at /mcp/<name>" do
      expect(draw { mcp_server :support }).to eq([ { path: "/mcp/support", name: "support_mcp_server", server: "SupportServer" } ])
    end

    it "dasherizes the default path" do
      expect(draw { mcp_server :customer_support }.first[:path]).to eq("/mcp/customer-support")
    end

    it "supports namespaced servers" do
      expect(draw { mcp_server "admin/billing" }).to eq([ { path: "/mcp/admin/billing", name: "admin_billing_mcp_server", server: "Admin::BillingServer" } ])
    end

    it "accepts path, as and server overrides" do
      routes = draw { mcp_server :support, path: "/internal/mcp", as: :internal_mcp, server: "HelpdeskServer" }

      expect(routes).to eq([ { path: "/internal/mcp", name: "internal_mcp", server: "HelpdeskServer" } ])
    end

    it "accepts a server class" do
      stub_const("ClassRoutingServer", Class.new(OmniAgent::MCP::Server))

      expect(draw { mcp_server :tools, server: ClassRoutingServer }.first[:server]).to eq("ClassRoutingServer")
    end
  end

  describe "#mcp_servers" do
    it "mounts each named server" do
      expect(draw { mcp_servers :support, :billing }.map { |route| route[:server] }).to eq(%w[SupportServer BillingServer])
    end

    it "discovers servers from the directory when called without names" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "admin"))
        FileUtils.mkdir_p(File.join(dir, "support_server", "tools"))
        %w[support_server.rb admin/billing_server.rb application_mcp_server.rb support_server/tools/lookup_server.rb helpers.rb].each do |file|
          File.write(File.join(dir, file), "")
        end

        routes = draw { mcp_servers directory: dir }

        expect(routes.map { |route| [ route[:path], route[:server] ] }).to eq([
          [ "/mcp/admin/billing", "Admin::BillingServer" ],
          [ "/mcp/support", "SupportServer" ]
        ])
      end
    end

    it "skips excluded servers" do
      routes = draw { mcp_servers :support, :billing, except: [ :billing ] }

      expect(routes.map { |route| route[:server] }).to eq(%w[SupportServer])
    end

    it "mounts nothing when the directory does not exist" do
      expect(draw { mcp_servers directory: "/nonexistent/mcp_servers" }).to eq([])
    end

    it "uses app/mcp_servers by default" do
      expect(draw { mcp_servers }.map { |route| route[:server] }).to eq(%w[ResearchServer])
    end
  end

  describe ".slug_for" do
    it "normalizes symbols, file names and class names" do
      expect([ :support, "support_server", "SupportServer", "Admin::SupportServer" ].map { |name| described_class.slug_for(name) })
        .to eq(%w[support support support admin/support])
    end
  end
end
