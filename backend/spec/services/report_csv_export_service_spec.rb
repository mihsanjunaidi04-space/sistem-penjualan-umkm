require "rails_helper"

RSpec.describe ReportCsvExportService do
  let(:period) { ReportingPeriod.new(from: "2026-01-01", to: "2026-01-02") }

  def rows(csv)
    CSV.parse(csv.delete_prefix("\uFEFF"), headers: true)
  end

  def create_verified_order
    suffix = SecureRandom.hex(5)
    customer = User.create!(name: "CSV Customer", email: "csv-customer-#{suffix}@example.com", password: "password123", role: "customer")
    admin = User.create!(name: "CSV Admin", email: "csv-admin-#{suffix}@example.com", password: "password123", role: "admin")
    shipping = ShippingMethod.create!(name: "CSV Shipping #{suffix}", estimated_days: 2, cost: 500, is_active: true)
    order = Order.create!(
      order_number: "CSV-#{suffix}", user: customer, shipping_method: shipping, status: "processing",
      subtotal: 400, shipping_cost: 500, total_amount: 900,
      payment_deadline_at: period.start_at + 12.hours, created_at: period.start_at
    )
    payment = Payment.create!(order:, payment_method: "manual_transfer", amount: 900, status: "paid", verified_at: period.start_at)
    category = Category.create!(name: "CSV Category #{suffix}", slug: "csv-category-#{suffix}")
    product = Product.create!(
      category:, name: "CSV Product", slug: "csv-product-#{suffix}", sku: "CSV-#{suffix}", price: 200,
      stock_on_hand: 10, reserved_stock: 0, is_active: true
    )
    OrderItem.create!(
      order:, product:, product_name_snapshot: "CSV Product Snapshot", sku_snapshot: "CSV-SNAPSHOT",
      unit_price: 200, quantity: 2, subtotal: 400
    )
    Refund.create!(
      payment:, order:, amount: 100, reason: "CSV test refund", status: "processed", processed_by: admin,
      processed_at: period.start_at + 1.hour, reference_number: "CSV-REF-#{suffix}"
    )
  end

  it "exports sales and order series from their JSON report services" do
    sales_data = {
      series: [
        { bucket: "2026-01-01", orders_count: 1, products_quantity: 2, product_gross_amount: 300,
          verified_payment_amount: 400, processed_refund_amount: 0, net_receipts_amount: 400 }
      ]
    }
    order_data = {
      series: [
        { period: "2026-01-01", total_orders: 1,
          by_status: OrderReportService::ORDER_STATUSES.index_with { |status| status == "processing" ? 1 : 0 } }
      ]
    }
    allow(SalesReportService).to receive(:call).and_return(sales_data)
    allow(OrderReportService).to receive(:call).and_return(order_data)

    sales_export = described_class.call(report: "sales", period:, group_by: "day")
    order_export = described_class.call(report: "orders", period:, group_by: "day")

    expect(rows(sales_export.body).headers).to eq(ReportCsvExportService::CSV_HEADERS.fetch("sales"))
    expect(rows(sales_export.body).first.fields).to eq([ "2026-01-01", "1", "2", "300", "400", "0", "400" ])
    expect(sales_export.filename).to eq("sales-day-2026-01-01-to-2026-01-02.csv")
    expect(rows(order_export.body).headers).to eq(ReportCsvExportService::CSV_HEADERS.fetch("orders"))
    expect(rows(order_export.body).first.fields).to eq([ "2026-01-01", "1", "0", "1", "0", "0", "0" ])
  end

  it "matches sales and order CSV rows to the actual JSON report series" do
    create_verified_order
    sales_json = SalesReportService.call(period:, group_by: "day")
    orders_json = OrderReportService.call(period:, group_by: "day")

    sales_csv = rows(described_class.call(report: "sales", period:, group_by: "day").body).first
    orders_csv = rows(described_class.call(report: "orders", period:, group_by: "day").body).first

    expect(sales_csv.fields).to eq(ReportCsvExportService::CSV_HEADERS.fetch("sales").map { |key| sales_json[:series].first.fetch(key.to_sym).to_s })
    expect(orders_csv.fields).to eq([
      orders_json[:series].first.fetch(:period),
      orders_json[:series].first.fetch(:total_orders).to_s,
      *OrderReportService::ORDER_STATUSES.map { |status| orders_json[:series].first.fetch(:by_status).fetch(status).to_s }
    ])
  end

  it "streams every product batch and neutralizes dangerous text without changing numeric fields" do
    product_rows = [
      { product_id: 1, name: "=1+1", sku: "=SKU-1", quantity: 1, gross_amount: 100 },
      { product_id: 2, name: "+SUM(A1)", sku: "SKU,\"2\"", quantity: 2, gross_amount: 200 },
      { product_id: 3, name: "-cmd", sku: "SKU-3", quantity: 3, gross_amount: 300 },
      { product_id: 4, name: "@value", sku: "SKU-4", quantity: 4, gross_amount: 400 },
      { product_id: 5, name: "\tformula", sku: "SKU-5", quantity: 5, gross_amount: 500 },
      { product_id: 6, name: "\nformula", sku: "SKU-6", quantity: 6, gross_amount: -600 },
      { product_id: 7, name: "A, \"quoted\"\nname", sku: "SKU-7", quantity: 7, gross_amount: 700 }
    ]
    allow(ProductReportService).to receive(:export_count).with(period:).and_return(product_rows.length)
    allow(ProductReportService).to receive(:each_export_batch).with(period:)
      .and_yield(product_rows[0]).and_yield(product_rows[1]).and_yield(product_rows[2])
      .and_yield(product_rows[3]).and_yield(product_rows[4]).and_yield(product_rows[5]).and_yield(product_rows[6])

    export = described_class.call(report: "products", period:)
    parsed = rows(export.body)

    expect(parsed.headers).to eq(%w[product_id name sku quantity gross_amount])
    expect(parsed.map { |row| row["name"] }.first(6)).to eq(product_rows.first(6).map { |row| "'#{row[:name]}" })
    expect(parsed.first["sku"]).to eq("'=SKU-1")
    expect(parsed[1]["sku"]).to eq("SKU,\"2\"")
    expect(parsed[5]["gross_amount"]).to eq("-600")
    expect(parsed[6]["name"]).to eq("A, \"quoted\"\nname")
    expect(export.filename).to eq("products-2026-01-01-to-2026-01-02.csv")
    expect(export.body.encoding).to eq(Encoding::UTF_8)
  end

  it "rejects an oversized product export before reading any product batches" do
    allow(ProductReportService).to receive(:export_count).with(period:).and_return(10_001)
    expect(ProductReportService).not_to receive(:each_export_batch)

    expect { described_class.call(report: "products", period:) }
      .to raise_error(ReportCsvExportService::Error) { |error|
        expect(error.code).to eq("export_limit_exceeded")
        expect(error.details).to eq(max_rows: 10_000)
      }
  end

  it "allows exactly the maximum product row count" do
    allow(ProductReportService).to receive(:export_count).with(period:).and_return(10_000)
    allow(ProductReportService).to receive(:each_export_batch).with(period:) do |**_options, &block|
      10_000.times do |index|
        block.call(product_id: index + 1, name: "Product", sku: "SKU", quantity: 1, gross_amount: 1)
      end
    end

    export = described_class.call(report: "products", period:)

    expect(export.body.lines.length).to eq(10_001)
  end

  it "rejects oversized bucket sets before generating CSV" do
    allow(SalesReportService).to receive(:call).and_return(series: Array.new(10_001) { {} })

    expect { described_class.call(report: "sales", period:, group_by: "day") }
      .to raise_error(ReportCsvExportService::Error) { |error| expect(error.code).to eq("export_limit_exceeded") }
  end

  it "keeps an empty export header and rejects unsupported report/group combinations" do
    allow(SalesReportService).to receive(:call).and_return(series: [])
    allow(ProductReportService).to receive(:export_count).with(period:).and_return(0)
    allow(ProductReportService).to receive(:each_export_batch).with(period:)

    expect(rows(described_class.call(report: "sales", period:).body).length).to eq(0)
    expect(rows(described_class.call(report: "products", period:).body).headers).to eq(%w[product_id name sku quantity gross_amount])
    expect { described_class.call(report: "dashboard", period:) }
      .to raise_error(ReportCsvExportService::Error) { |error| expect(error.code).to eq("REPORT_TYPE_INVALID") }
    expect { described_class.call(report: "products", period:, group_by: "day") }
      .to raise_error(ReportCsvExportService::Error) { |error| expect(error.code).to eq("REPORT_GROUP_BY_INVALID") }
  end
end
