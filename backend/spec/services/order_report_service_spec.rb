require "rails_helper"

RSpec.describe OrderReportService do
  STATUSES = %w[awaiting_payment processing shipped completed cancelled].freeze

  def customer
    suffix = SecureRandom.hex(5)
    User.create!(name: "Order Report #{suffix}", email: "order-report-#{suffix}@example.com", password: "password123", role: "customer")
  end

  def shipping_method
    ShippingMethod.create!(name: "Order Report Ship #{SecureRandom.hex(4)}", estimated_days: 2, cost: 0, is_active: true)
  end

  def wita_time(year, month, day, hour = 0)
    Time.utc(year, month, day, hour) - 8.hours
  end

  def create_order(status:, created_at:, payment_status: nil)
    order = Order.create!(
      order_number: "ORDER-REPORT-#{SecureRandom.hex(5)}",
      user: customer,
      shipping_method: shipping_method,
      status: status,
      subtotal: 1_000,
      shipping_cost: 0,
      total_amount: 1_000,
      payment_deadline_at: created_at + 12.hours,
      created_at: created_at
    )
    Payment.create!(order: order, payment_method: "manual_transfer", amount: 1_000, status: payment_status) if payment_status
    order
  end

  it "counts all current statuses by WITA creation bucket, regardless of payment status" do
    period = ReportingPeriod.new(from: "2026-01-01", to: "2026-01-03")
    STATUSES.each do |status|
      create_order(status: status, created_at: wita_time(2026, 1, 1, 2), payment_status: "rejected")
    end
    create_order(status: "processing", created_at: wita_time(2026, 1, 3, 4), payment_status: "paid")

    result = described_class.call(period: period)

    expect(result[:totals]).to eq(total_orders: 6, by_status: {
      "awaiting_payment" => 1, "processing" => 2, "shipped" => 1, "completed" => 1, "cancelled" => 1
    })
    expect(result[:series].map { |bucket| bucket[:period] }).to eq(%w[2026-01-01 2026-01-02 2026-01-03])
    expect(result[:series][0][:total_orders]).to eq(5)
    expect(result[:series][1]).to eq(period: "2026-01-02", total_orders: 0, by_status: STATUSES.index_with { 0 })
    expect(result[:series][2][:by_status]).to eq(STATUSES.index_with { |status| status == "processing" ? 1 : 0 })
    expect(result[:series].sum { |bucket| bucket[:total_orders] }).to eq(6)
  end

  it "groups monthly across year boundaries and includes empty months" do
    create_order(status: "cancelled", created_at: wita_time(2025, 12, 31, 18))
    create_order(status: "completed", created_at: wita_time(2026, 2, 1, 1))
    period = ReportingPeriod.new(from: "2025-12-01", to: "2026-02-28")

    result = described_class.call(period: period, group_by: "month")

    expect(result[:series].map { |bucket| bucket[:period] }).to eq(%w[2025-12 2026-01 2026-02])
    expect(result[:series].map { |bucket| bucket[:total_orders] }).to eq([ 1, 0, 1 ])
    expect(result[:totals][:by_status]).to eq(STATUSES.index_with { |status| status == "cancelled" || status == "completed" ? 1 : 0 })
  end

  it "includes the WITA start and last instant and excludes both outside boundaries" do
    period = ReportingPeriod.new(from: "2026-04-10", to: "2026-04-10")
    create_order(status: "processing", created_at: period.start_at - 1.second)
    create_order(status: "awaiting_payment", created_at: period.start_at)
    create_order(status: "shipped", created_at: period.end_at - 1.second)
    create_order(status: "cancelled", created_at: period.end_at)

    result = described_class.call(period: period)

    expect(result[:totals][:total_orders]).to eq(2)
    expect(result[:totals][:by_status]).to eq(STATUSES.index_with { |status| %w[awaiting_payment shipped].include?(status) ? 1 : 0 })
  end

  it "rejects unsupported grouping" do
    period = ReportingPeriod.new(from: "2026-01-01", to: "2026-01-01")

    expect { described_class.call(period: period, group_by: "year") }
      .to raise_error(OrderReportService::Error) { |error| expect(error.code).to eq("REPORT_GROUP_BY_INVALID") }
  end
end
