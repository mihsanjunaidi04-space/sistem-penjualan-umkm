require "rails_helper"

RSpec.describe InventoryReportService do
  def product(name:, stock_on_hand: 0, reserved_stock: 0, is_active: true)
    suffix = SecureRandom.hex(4)
    category = Category.create!(name: "Inventory Report #{suffix}", slug: "inventory-report-#{suffix}")
    Product.create!(
      category:, name:, slug: "#{name.parameterize}-#{suffix}", sku: "INV-#{suffix}", price: 1_000,
      stock_on_hand:, reserved_stock:, is_active:
    )
  end

  def movement(product:, type:, quantity:, created_at:, order: nil)
    InventoryMovement.create!(
      product:, order:, movement_type: type, quantity:, stock_before: product.stock_on_hand,
      stock_after: product.stock_on_hand, created_at:
    )
  end

  def wita_time(year, month, day, hour = 0)
    Time.utc(year, month, day, hour) - 8.hours
  end

  it "separates current stock snapshots from period physical movements and paginates without losing totals" do
    period = ReportingPeriod.new(from: "2026-02-10", to: "2026-02-10")
    baseline = described_class.call(period:, per_page: 1)
    baseline_products = baseline.dig(:pagination, :total_count)
    baseline_stock = Product.where("stock_on_hand > 0 OR reserved_stock > 0").pick(
      Arel.sql("COALESCE(SUM(stock_on_hand), 0)"), Arel.sql("COALESCE(SUM(reserved_stock), 0)")
    ) || [ 0, 0 ]
    baseline_movements = InventoryMovement.where(
      movement_type: %w[stock_in stock_out], created_at: period.start_at...period.end_at
    ).pick(
      Arel.sql("COALESCE(SUM(CASE WHEN movement_type = 'stock_in' THEN ABS(quantity) ELSE 0 END), 0)"),
      Arel.sql("COALESCE(SUM(CASE WHEN movement_type = 'stock_out' THEN ABS(quantity) ELSE 0 END), 0)")
    ) || [ 0, 0 ]
    stocked = product(name: "Stocked", stock_on_hand: 10, reserved_stock: 4)
    inactive_moved = product(name: "Inactive Moved", is_active: false)
    irrelevant = product(name: "No Stock No Movement")

    movement(product: stocked, type: "stock_in", quantity: 5, created_at: period.start_at)
    movement(product: stocked, type: "stock_out", quantity: -3, created_at: period.end_at - 1.second)
    movement(product: stocked, type: "reservation", quantity: 4, created_at: period.start_at + 1.hour)
    movement(product: stocked, type: "reservation_release", quantity: -4, created_at: period.start_at + 2.hours)
    movement(product: stocked, type: "adjustment", quantity: 2, created_at: period.start_at + 3.hours)
    movement(product: stocked, type: "stock_in", quantity: 7, created_at: period.start_at - 1.second)
    movement(product: inactive_moved, type: "stock_out", quantity: -2, created_at: period.start_at + 4.hours)
    movement(product: irrelevant, type: "stock_out", quantity: -6, created_at: period.end_at)

    first_page = described_class.call(period:, per_page: 1)
    stocked_page = described_class.call(period:, page: baseline_products + 1, per_page: 1)
    inactive_page = described_class.call(period:, page: baseline_products + 2, per_page: 1)

    expect(first_page[:totals]).to eq(
      total_products: baseline_products + 2,
      stock_on_hand: baseline_stock[0] + 10,
      reserved_stock: baseline_stock[1] + 4,
      available_stock: baseline_stock[0] - baseline_stock[1] + 6,
      stock_in_quantity: baseline_movements[0] + 5,
      stock_out_quantity: baseline_movements[1] + 5
    )
    report_products = stocked_page[:products] + inactive_page[:products]
    expect(report_products.find { |row| row[:product_id] == stocked.id }).to include(
      name: "Stocked", sku: stocked.sku, is_active: true, stock_on_hand: 10, reserved_stock: 4,
      available_stock: 6, stock_in_quantity: 5, stock_out_quantity: 3
    )
    expect(report_products.find { |row| row[:product_id] == inactive_moved.id }).to include(
      is_active: false, stock_in_quantity: 0, stock_out_quantity: 2
    )
    expect(stocked_page[:pagination]).to eq(page: baseline_products + 1, per_page: 1, total_count: baseline_products + 2, total_pages: baseline_products + 2)
    expect(inactive_page[:totals]).to eq(first_page[:totals])
    all_report_ids = (1..(baseline_products + 2)).flat_map do |page|
      described_class.call(period:, page:, per_page: 1)[:products].map { |row| row[:product_id] }
    end
    expect(all_report_ids).to include(stocked.id, inactive_moved.id)
    expect(all_report_ids).not_to include(irrelevant.id)
  end

  it "uses inclusive WITA dates with a UTC half-open movement interval" do
    period = ReportingPeriod.new(from: "2026-04-10", to: "2026-04-10")
    record = product(name: "WITA Boundary")
    movement(product: record, type: "stock_in", quantity: 2, created_at: period.start_at)
    movement(product: record, type: "stock_in", quantity: 3, created_at: period.end_at - 1.second)
    movement(product: record, type: "stock_in", quantity: 9, created_at: period.start_at - 1.second)
    movement(product: record, type: "stock_in", quantity: 11, created_at: period.end_at)

    result = described_class.call(period:)

    expect(result[:period]).to eq(from: "2026-04-10", to: "2026-04-10", timezone: "Asia/Makassar")
    expect(result[:totals]).to include(stock_in_quantity: 5, stock_out_quantity: 0)
  end

  it "returns stable results for a period without movements and validates pagination" do
    period = ReportingPeriod.new(from: "2090-01-01", to: "2090-01-01")
    baseline = described_class.call(period:)

    result = described_class.call(period:)

    expect(result).to eq(baseline)
    [ { page: "0" }, { page: "1.5" }, { per_page: "101" } ].each do |pagination|
      expect { described_class.call(period:, **pagination) }
        .to raise_error(InventoryReportService::Error) { |error| expect(error.code).to eq("REPORT_PAGINATION_INVALID") }
    end
  end
end
