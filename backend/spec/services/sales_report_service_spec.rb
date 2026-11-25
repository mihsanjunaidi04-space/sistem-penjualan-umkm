require "rails_helper"

RSpec.describe SalesReportService do
  def user(role: "customer")
    suffix = SecureRandom.hex(5)
    User.create!(name: "Sales Report #{suffix}", email: "sales-report-#{suffix}@example.com", password: "password123", role:)
  end

  def wita_time(year, month, day, hour = 0, minute = 0)
    Time.utc(year, month, day, hour, minute) - 8.hours
  end

  def product(name)
    suffix = SecureRandom.hex(4)
    category = Category.create!(name: "Sales Category #{suffix}", slug: "sales-category-#{suffix}")
    Product.create!(category:, name:, slug: "#{name.parameterize}-#{suffix}", sku: "SALES-#{suffix}", price: 1_000, stock_on_hand: 10, reserved_stock: 0, is_active: true)
  end

  def order_with_payment(customer:, status:, amount:, created_at:, verified_at:)
    shipping_method = ShippingMethod.create!(name: "Sales Ship #{SecureRandom.hex(4)}", estimated_days: 2, cost: 100, is_active: true)
    order = Order.create!(
      order_number: "SALES-#{SecureRandom.hex(5)}",
      user: customer,
      shipping_method:,
      status: "processing",
      subtotal: amount - 100,
      shipping_cost: 100,
      total_amount: amount,
      payment_deadline_at: created_at + 12.hours,
      created_at:
    )
    payment = Payment.create!(order:, payment_method: "manual_transfer", amount:, status:, verified_at:)
    [ order, payment ]
  end

  def add_item(order:, product:, quantity:, subtotal:)
    OrderItem.create!(order:, product:, product_name_snapshot: product.name, sku_snapshot: product.sku, unit_price: subtotal / quantity, quantity:, subtotal:)
  end

  def sample_transactions
    admin = user(role: "admin")
    customer = user
    product_one = product("Widget One")
    product_two = product("Widget Two")

    december_order, december_payment = order_with_payment(
      customer:, status: "paid", amount: 1_100,
      created_at: wita_time(2025, 12, 31, 10), verified_at: wita_time(2026, 1, 1, 0, 30)
    )
    add_item(order: december_order, product: product_one, quantity: 2, subtotal: 400)
    add_item(order: december_order, product: product_two, quantity: 1, subtotal: 300)
    Refund.create!(payment: december_payment, order: december_order, amount: 50, reason: "partial one", status: "processed", processed_by: admin, processed_at: wita_time(2026, 1, 2, 2), reference_number: "SALES-R1")
    Refund.create!(payment: december_payment, order: december_order, amount: 25, reason: "partial two", status: "processed", processed_by: admin, processed_at: wita_time(2026, 1, 2, 3), reference_number: "SALES-R2")
    Refund.create!(payment: december_payment, order: december_order, amount: 100, reason: "pending", status: "pending")
    Refund.create!(payment: december_payment, order: december_order, amount: 25, reason: "rejected", status: "rejected", notes: "Rejected")

    january_order, january_payment = order_with_payment(
      customer:, status: "refunded", amount: 500,
      created_at: wita_time(2026, 1, 1, 22), verified_at: wita_time(2026, 1, 2, 1)
    )
    add_item(order: january_order, product: product_one, quantity: 1, subtotal: 200)
    Refund.create!(payment: january_payment, order: january_order, amount: 500, reason: "full", status: "processed", processed_by: admin, processed_at: wita_time(2026, 1, 2, 4), reference_number: "SALES-R3")

    rejected_order, = order_with_payment(
      customer:, status: "rejected", amount: 900,
      created_at: wita_time(2026, 1, 1, 12), verified_at: wita_time(2026, 1, 1, 13)
    )
    add_item(order: rejected_order, product: product_one, quantity: 10, subtotal: 2_000)
  end

  it "groups daily metrics by their own WITA timestamps and reconciles with the dashboard" do
    sample_transactions
    period = ReportingPeriod.new(from: "2025-12-30", to: "2026-01-03")

    result = described_class.call(period:, group_by: "day")
    dashboard = DashboardSummaryService.call(period:)

    expect(result[:period]).to eq(from: "2025-12-30", to: "2026-01-03", timezone: "Asia/Makassar")
    expect(result[:group_by]).to eq("day")
    expect(result[:series].map { |row| row[:bucket] }).to eq(%w[2025-12-30 2025-12-31 2026-01-01 2026-01-02 2026-01-03])
    expect(result[:series].first.except(:bucket).values).to all(eq(0))
    expect(result[:series].last.except(:bucket).values).to all(eq(0))
    expect(result[:series].find { |row| row[:bucket] == "2025-12-31" }[:orders_count]).to eq(1)
    expect(result[:series].find { |row| row[:bucket] == "2026-01-01" }).to include(orders_count: 2, verified_payment_amount: 1_100, products_quantity: 3, product_gross_amount: 700)
    expect(result[:series].find { |row| row[:bucket] == "2026-01-02" }).to include(verified_payment_amount: 500, processed_refund_amount: 575, net_receipts_amount: -75, products_quantity: 1, product_gross_amount: 200)
    expect(result[:totals]).to eq(
      orders_count: 3,
      products_quantity: 4,
      product_gross_amount: 900,
      verified_payment_amount: 1_600,
      processed_refund_amount: 575,
      net_receipts_amount: 1_025
    )
    expect(result[:totals][:verified_payment_amount]).to eq(dashboard.dig(:summary, :verified_payments, :amount))
    expect(result[:totals][:processed_refund_amount]).to eq(dashboard.dig(:summary, :processed_refunds, :amount))
    expect(result[:totals][:net_receipts_amount]).to eq(dashboard.dig(:summary, :net_receipts))
    expect(result[:totals][:products_quantity]).to eq(dashboard.dig(:summary, :products_sold, :quantity))
    expect(result[:totals][:product_gross_amount]).to eq(dashboard.dig(:summary, :products_sold, :gross_subtotal))
  end

  it "returns chronological monthly buckets including empty months across a year boundary" do
    sample_transactions
    period = ReportingPeriod.new(from: "2025-11-15", to: "2026-02-10")

    result = described_class.call(period:, group_by: "month")

    expect(result[:series].map { |row| row[:bucket] }).to eq(%w[2025-11 2025-12 2026-01 2026-02])
    expect(result[:series].first.except(:bucket).values).to all(eq(0))
    expect(result[:series].last.except(:bucket).values).to all(eq(0))
    expect(result[:series].find { |row| row[:bucket] == "2026-01" }).to include(orders_count: 2, verified_payment_amount: 1_600, processed_refund_amount: 575)
    expect(result[:totals][:net_receipts_amount]).to eq(1_025)
  end

  it "includes the WITA start instant and excludes the instant at the exclusive end" do
    customer = user
    item_product = product("Boundary Widget")
    period = ReportingPeriod.new(from: "2024-02-29", to: "2024-02-29")
    start_order, = order_with_payment(customer:, status: "paid", amount: 600, created_at: period.start_at, verified_at: period.start_at)
    add_item(order: start_order, product: item_product, quantity: 1, subtotal: 500)
    end_order, = order_with_payment(customer:, status: "paid", amount: 800, created_at: period.end_at, verified_at: period.end_at)
    add_item(order: end_order, product: item_product, quantity: 2, subtotal: 700)

    result = described_class.call(period:, group_by: "day")

    expect(result[:series].map { |row| row[:bucket] }).to eq([ "2024-02-29" ])
    expect(result[:totals]).to eq(orders_count: 1, products_quantity: 1, product_gross_amount: 500, verified_payment_amount: 600, processed_refund_amount: 0, net_receipts_amount: 600)
  end

  it "rejects group_by values other than day or month" do
    period = ReportingPeriod.new(from: "2026-01-01", to: "2026-01-01")

    expect { described_class.call(period:, group_by: "year") }
      .to raise_error(SalesReportService::Error) { |error| expect(error.code).to eq("REPORT_GROUP_BY_INVALID") }
  end
end
