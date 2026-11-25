require "rails_helper"

RSpec.describe ProductReportService do
  VERIFIED_STATUSES = %w[paid refunded].freeze

  def customer
    suffix = SecureRandom.hex(5)
    User.create!(name: "Product Report #{suffix}", email: "product-report-#{suffix}@example.com", password: "password123", role: "customer")
  end

  def admin
    suffix = SecureRandom.hex(5)
    User.create!(name: "Product Report Admin #{suffix}", email: "product-report-admin-#{suffix}@example.com", password: "password123", role: "admin")
  end

  def product(name, is_active: true)
    suffix = SecureRandom.hex(4)
    category = Category.create!(name: "Product Report Cat #{suffix}", slug: "product-report-cat-#{suffix}")
    Product.create!(category: category, name: name, slug: "#{name.parameterize}-#{suffix}", sku: "PR-#{suffix}", price: 1_000, stock_on_hand: 10, reserved_stock: 0, is_active: is_active)
  end

  def wita_time(year, month, day, hour = 0, minute = 0)
    Time.utc(year, month, day, hour, minute) - 8.hours
  end

  def create_payment(status:, verified_at:)
    shipping_method = ShippingMethod.create!(name: "Product Report Ship #{SecureRandom.hex(4)}", estimated_days: 2, cost: 500, is_active: true)
    created_at = verified_at - 2.hours
    order = Order.create!(
      order_number: "PRODUCT-REPORT-#{SecureRandom.hex(5)}",
      user: customer,
      shipping_method: shipping_method,
      status: status == "refunded" ? "completed" : "processing",
      subtotal: 3_000,
      shipping_cost: 500,
      total_amount: 3_500,
      payment_deadline_at: created_at + 12.hours,
      created_at: created_at
    )
    payment = Payment.create!(order: order, payment_method: "manual_transfer", amount: 3_500, status: status, verified_at: verified_at)
    [ order, payment ]
  end

  def add_item(order:, product:, quantity:, subtotal:, name_snapshot: product.name, sku_snapshot: product.sku)
    OrderItem.create!(order: order, product: product, product_name_snapshot: name_snapshot, sku_snapshot: sku_snapshot, unit_price: subtotal / quantity, quantity: quantity, subtotal: subtotal)
  end

  it "aggregates paid and refunded sales by product while separating refunds and excluding rejected payments" do
    period = ReportingPeriod.new(from: "2026-01-01", to: "2026-01-03")
    item_product = product("Current Name")
    inactive_product = product("Inactive Product", is_active: false)
    unsold_product = product("Unsold Product")
    admin_record = admin

    first_order, first_payment = create_payment(status: "paid", verified_at: wita_time(2026, 1, 1, 8))
    add_item(order: first_order, product: item_product, quantity: 2, subtotal: 1_200, name_snapshot: "Old Name", sku_snapshot: "OLD-SKU")
    add_item(order: first_order, product: inactive_product, quantity: 1, subtotal: 800)

    second_order, second_payment = create_payment(status: "refunded", verified_at: wita_time(2026, 1, 2, 10))
    add_item(order: second_order, product: item_product, quantity: 3, subtotal: 1_800, name_snapshot: "Earlier Name", sku_snapshot: "EARLIER-SKU")

    rejected_order, = create_payment(status: "rejected", verified_at: wita_time(2026, 1, 2, 11))
    add_item(order: rejected_order, product: item_product, quantity: 10, subtotal: 9_000)

    item_product.update!(name: "Current Name Updated", sku: "CURRENT-SKU")
    inactive_product.update!(is_active: false)

    Refund.create!(payment: second_payment, order: second_order, amount: 400, reason: "processed partial", status: "processed", processed_by: admin_record, processed_at: wita_time(2026, 1, 3, 1), reference_number: "PRODUCT-R1")
    Refund.create!(payment: first_payment, order: first_order, amount: 200, reason: "processed outside period", status: "processed", processed_by: admin_record, processed_at: wita_time(2026, 1, 4, 1), reference_number: "PRODUCT-R2")
    Refund.create!(payment: first_payment, order: first_order, amount: 100, reason: "pending", status: "pending")
    Refund.create!(payment: first_payment, order: first_order, amount: 50, reason: "rejected", status: "rejected", notes: "Not approved")

    result = described_class.call(period: period)

    expect(result[:totals]).to eq(total_quantity: 6, gross_product_amount: 3_800, processed_refund_amount: 400, total_products_sold: 2)
    expect(result[:products]).to eq([
      { product_id: item_product.id, name: "Current Name Updated", sku: "CURRENT-SKU", quantity: 5, gross_amount: 3_000 },
      { product_id: inactive_product.id, name: "Inactive Product", sku: inactive_product.sku, quantity: 1, gross_amount: 800 }
    ])
    expect(result[:products].map { |row| row[:product_id] }).not_to include(unsold_product.id)
  end

  it "uses verified_at WITA boundaries for the inclusive period" do
    product_record = product("Boundary Product")
    period = ReportingPeriod.new(from: "2026-04-10", to: "2026-04-10")
    outside_order, = create_payment(status: "paid", verified_at: period.start_at - 1.second)
    start_order, = create_payment(status: "paid", verified_at: period.start_at)
    end_order, = create_payment(status: "refunded", verified_at: period.end_at - 1.second)
    after_order, = create_payment(status: "paid", verified_at: period.end_at)
    add_item(order: outside_order, product: product_record, quantity: 10, subtotal: 10_000)
    add_item(order: start_order, product: product_record, quantity: 1, subtotal: 100)
    add_item(order: end_order, product: product_record, quantity: 2, subtotal: 300)
    add_item(order: after_order, product: product_record, quantity: 20, subtotal: 20_000)

    result = described_class.call(period: period)

    expect(result[:totals]).to include(total_quantity: 3, gross_product_amount: 400, total_products_sold: 1)
  end

  it "sorts by gross amount then product id and paginates in SQL without changing totals" do
    period = ReportingPeriod.new(from: "2026-06-01", to: "2026-06-01")
    first_product = product("Tie First")
    second_product = product("Tie Second")
    third_product = product("Higher Gross")
    order, = create_payment(status: "paid", verified_at: wita_time(2026, 6, 1, 9))
    add_item(order: order, product: first_product, quantity: 1, subtotal: 500)
    add_item(order: order, product: second_product, quantity: 5, subtotal: 500)
    add_item(order: order, product: third_product, quantity: 1, subtotal: 700)

    first_page = described_class.call(period: period, page: "1", per_page: "1")
    second_page = described_class.call(period: period, page: "2", per_page: "1")
    empty_page = described_class.call(period: period, page: "4", per_page: "1")

    expect(first_page[:products].first[:product_id]).to eq(third_product.id)
    expect(second_page[:products].first[:product_id]).to eq(first_product.id)
    expect(first_page[:totals]).to eq(total_quantity: 7, gross_product_amount: 1_700, processed_refund_amount: 0, total_products_sold: 3)
    expect(second_page[:totals]).to eq(first_page[:totals])
    expect(empty_page[:products]).to eq([])
    expect(empty_page[:pagination]).to eq(page: 4, per_page: 1, total_count: 3, total_pages: 3)
  end

  it "rejects invalid page and per_page values" do
    period = ReportingPeriod.new(from: "2026-01-01", to: "2026-01-01")

    [ { page: "0" }, { page: "1.5" }, { page: "abc" }, { per_page: "0" }, { per_page: "101" } ].each do |pagination|
      expect { described_class.call(period: period, **pagination) }
        .to raise_error(ProductReportService::Error) { |error| expect(error.code).to eq("REPORT_PAGINATION_INVALID") }
    end
  end

  it "accepts the maximum page size" do
    period = ReportingPeriod.new(from: "2026-01-01", to: "2026-01-01")

    result = described_class.call(period: period, per_page: "100")

    expect(result[:pagination]).to eq(page: 1, per_page: 100, total_count: 0, total_pages: 0)
  end

  it "exports every grouped product in stable SQL batches independently of JSON pagination" do
    period = ReportingPeriod.new(from: "2026-07-01", to: "2026-07-01")
    products = [ product("Batch A"), product("Batch B"), product("Batch C") ]
    order, = create_payment(status: "paid", verified_at: wita_time(2026, 7, 1, 12))
    products.each_with_index do |record, index|
      add_item(order:, product: record, quantity: index + 1, subtotal: (index + 1) * 100)
    end

    json_page = described_class.call(period:, per_page: 1)
    exported_rows = described_class.each_export_batch(period:).to_a

    expect(json_page[:products].length).to eq(1)
    expect(exported_rows.length).to eq(3)
    expect(exported_rows.map { |row| row[:product_id] }).to eq(products.reverse.map(&:id))
    expect(exported_rows.sum { |row| row[:quantity] }).to eq(json_page[:totals][:total_quantity])
    expect(exported_rows.sum { |row| row[:gross_amount] }).to eq(json_page[:totals][:gross_product_amount])
  end
end
