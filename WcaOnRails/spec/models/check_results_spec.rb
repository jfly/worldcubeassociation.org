# frozen_string_literal: true
require 'rails_helper'

describe CheckResults do
  let(:competition) { FactoryGirl.create(:competition) }
  let(:check_results) { CheckResults.new(competition_id: competition.id) }

  it "is valid" do
    expect(check_results).to be_valid
  end

  it "competition_id must exist" do
    check_results.competition_id = "blah blah"
    expect(check_results).to be_invalid
    expect(check_results.errors.messages[:competition_id]).not_to be_nil
  end

  it "event id must exist" do
    check_results.event_id = "blah blah"
    expect(check_results).to be_invalid
    expect(check_results.errors.messages[:event_id]).not_to be_nil
  end

  context "warnings" do
    it "yep<<<" do
      #<<<
    end
  end
end
