# frozen_string_literal: true

RSpec.describe QueryGuard do
  it "has a version number" do
    expect(QueryGuard::VERSION).not_to be nil
  end

  it "provides a configuration interface" do
    expect(QueryGuard.config).to be_a(QueryGuard::Config)
  end

  it "provides a trace interface" do
    result, report = QueryGuard.trace("test") { "result" }
    expect(result).to eq("result")
    expect(report).to be_a(QueryGuard::Trace::Report)
  end
end
