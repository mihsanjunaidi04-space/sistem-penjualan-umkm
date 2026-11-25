require "rails_helper"

RSpec.describe ReportingPeriod do
  it "converts inclusive WITA dates to a half-open UTC interval" do
    period = described_class.new(from: "2026-03-01", to: "2026-03-02")

    expect(period.start_at).to eq(Time.utc(2026, 2, 28, 16))
    expect(period.end_at).to eq(Time.utc(2026, 3, 2, 16))
  end

  it "accepts a 366-day period and rejects 367 days" do
    expect { described_class.new(from: "2025-01-01", to: "2026-01-01") }.not_to raise_error
    expect { described_class.new(from: "2025-01-01", to: "2026-01-02") }
      .to raise_error(ReportingPeriod::Error) { |error| expect(error.code).to eq("REPORT_PERIOD_TOO_LONG") }
  end

  it "rejects missing, invalid, ambiguous, and reversed dates" do
    [
      [ nil, "2026-01-01", "REPORT_PERIOD_REQUIRED" ],
      [ "2026-02-30", "2026-03-01", "REPORT_DATE_INVALID" ],
      [ "01/02/2026", "2026-03-01", "REPORT_DATE_INVALID" ],
      [ "2026-03-02", "2026-03-01", "REPORT_PERIOD_INVALID" ]
    ].each do |from, to, code|
      expect { described_class.new(from:, to:) }
        .to raise_error(ReportingPeriod::Error) { |error| expect(error.code).to eq(code) }
    end
  end
end
