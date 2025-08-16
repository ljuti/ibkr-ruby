# frozen_string_literal: true

RSpec.describe Ibkr do
  it "has a version number" do
    expect(Ibkr::VERSION).not_to be nil
  end

  it "does something useful" do
    expect(Ibkr).to be_a(Module)
    expect(Ibkr.configuration).to be_a(Ibkr::Configuration)
  end
end
