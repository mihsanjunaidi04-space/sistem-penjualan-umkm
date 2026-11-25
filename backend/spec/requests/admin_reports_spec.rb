require "rails_helper"

RSpec.describe "Admin reports API", type: :request do
  def user(role: "customer")
    suffix = SecureRandom.hex(5)
    User.create!(name: "Report User #{suffix}", email: "report-#{suffix}@example.com", password: "password123", role:)
  end

  def headers(record)
    { "Authorization" => "Bearer #{JwtService.encode({ user_id: record.id, role: record.role })}" }
  end

  let(:path) { "/admin/reports/dashboard?from=2026-03-01&to=2026-03-01" }

  it "allows admin and returns the dashboard summary without customer data" do
    admin = user(role: "admin")

    get path, headers: headers(admin)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.dig("data", "period")).to eq("from" => "2026-03-01", "to" => "2026-03-01", "timezone" => "Asia/Makassar")
    expect(body.dig("data", "summary", "net_receipts")).to eq(0)
    expect(body.to_s).not_to include("email", "address", "reference_number", "payment_proof")
  end

  it "rejects customer and unauthenticated access" do
    get path, headers: headers(user)
    expect(response).to have_http_status(:forbidden)

    get path
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns consistent validation errors for invalid or missing period parameters" do
    admin = user(role: "admin")

    get "/admin/reports/dashboard?from=2026-02-30&to=2026-03-01", headers: headers(admin)
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).dig("error", "code")).to eq("REPORT_DATE_INVALID")

    get "/admin/reports/dashboard", headers: headers(admin)
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).dig("error", "code")).to eq("REPORT_PERIOD_REQUIRED")
  end

  describe "GET /admin/reports/sales" do
    it "allows admins and defaults group_by to day" do
      admin = user(role: "admin")

      get "/admin/reports/sales?from=2090-01-01&to=2090-01-03", headers: headers(admin)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["success"]).to be(true)
      expect(json.dig("data", "group_by")).to eq("day")
      expect(json.dig("data", "period")).to eq("from" => "2090-01-01", "to" => "2090-01-03", "timezone" => "Asia/Makassar")
      expect(json.dig("data", "totals")).to eq(
        "orders_count" => 0,
        "products_quantity" => 0,
        "product_gross_amount" => 0,
        "verified_payment_amount" => 0,
        "processed_refund_amount" => 0,
        "net_receipts_amount" => 0
      )
      expect(json.dig("data", "series").map { |row| row["bucket"] }).to eq(%w[2090-01-01 2090-01-02 2090-01-03])
      expect(json.to_s).not_to include("email", "customer", "reference_number", "payment_proof")
    end

    it "accepts month grouping and returns all intersecting chronological months" do
      admin = user(role: "admin")

      get "/admin/reports/sales?from=2090-12-31&to=2091-02-01&group_by=month", headers: headers(admin)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.dig("data", "group_by")).to eq("month")
      expect(json.dig("data", "series").map { |row| row["bucket"] }).to eq(%w[2090-12 2091-01 2091-02])
      expect(json.dig("data", "series").all? { |row| row.except("bucket").values.all? { |value| value == 0 } }).to be(true)
    end

    it "rejects customers, unauthenticated requests, and an invalid grouping" do
      get "/admin/reports/sales?from=2090-01-01&to=2090-01-01", headers: headers(user)
      expect(response).to have_http_status(:forbidden)

      get "/admin/reports/sales?from=2090-01-01&to=2090-01-01"
      expect(response).to have_http_status(:unauthorized)

      admin = user(role: "admin")
      get "/admin/reports/sales?from=2090-01-01&to=2090-01-01&group_by=year", headers: headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body).dig("error", "code")).to eq("REPORT_GROUP_BY_INVALID")
    end

    it "rejects invalid, reversed, and overlong periods using dashboard errors" do
      admin = user(role: "admin")
      cases = [
        [ "from=2090-02-30&to=2090-03-01", "REPORT_DATE_INVALID" ],
        [ "from=2090-03-02&to=2090-03-01", "REPORT_PERIOD_INVALID" ],
        [ "from=2090-01-01&to=2091-01-02", "REPORT_PERIOD_TOO_LONG" ]
      ]

      cases.each do |query, code|
        get "/admin/reports/sales?#{query}", headers: headers(admin)
        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body).dig("error", "code")).to eq(code)
      end
    end
  end

  describe "GET /admin/reports/orders" do
    it "allows admins and returns the default daily report with every status" do
      admin = user(role: "admin")

      get "/admin/reports/orders?from=2090-01-01&to=2090-01-02", headers: headers(admin)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.dig("data", "group_by")).to eq("day")
      expect(json.dig("data", "period")).to eq("from" => "2090-01-01", "to" => "2090-01-02", "timezone" => "Asia/Makassar")
      expect(json.dig("data", "totals")).to eq(
        "total_orders" => 0,
        "by_status" => OrderReportService::ORDER_STATUSES.index_with { 0 }
      )
      expect(json.dig("data", "series").map { |row| row["period"] }).to eq(%w[2090-01-01 2090-01-02])
      expect(json.dig("data", "series").all? { |row| row["total_orders"].zero? && row["by_status"].values.all?(&:zero?) }).to be(true)
    end

    it "rejects customers, unauthenticated requests, and invalid report parameters" do
      get "/admin/reports/orders?from=2090-01-01&to=2090-01-01", headers: headers(user)
      expect(response).to have_http_status(:forbidden)

      get "/admin/reports/orders?from=2090-01-01&to=2090-01-01"
      expect(response).to have_http_status(:unauthorized)

      admin = user(role: "admin")
      [
        [ "from=2090-01-01", "REPORT_PERIOD_REQUIRED" ],
        [ "from=2090-1-1&to=2090-01-01", "REPORT_DATE_INVALID" ],
        [ "from=2090-02-30&to=2090-03-01", "REPORT_DATE_INVALID" ],
        [ "from=2090-03-02&to=2090-03-01", "REPORT_PERIOD_INVALID" ],
        [ "from=2090-01-01&to=2091-01-02", "REPORT_PERIOD_TOO_LONG" ],
        [ "from=2090-01-01&to=2090-01-01&group_by=year", "REPORT_GROUP_BY_INVALID" ]
      ].each do |query, code|
        get "/admin/reports/orders?#{query}", headers: headers(admin)
        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body).dig("error", "code")).to eq(code)
      end
    end
  end

  describe "GET /admin/reports/products" do
    it "allows admins and returns an empty paginated report without customer data" do
      admin = user(role: "admin")

      get "/admin/reports/products?from=2090-01-01&to=2090-01-02", headers: headers(admin)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.dig("data", "period")).to eq("from" => "2090-01-01", "to" => "2090-01-02", "timezone" => "Asia/Makassar")
      expect(json.dig("data", "totals")).to eq(
        "total_quantity" => 0,
        "gross_product_amount" => 0,
        "processed_refund_amount" => 0,
        "total_products_sold" => 0
      )
      expect(json.dig("data", "products")).to eq([])
      expect(json.dig("data", "pagination")).to eq("page" => 1, "per_page" => 20, "total_count" => 0, "total_pages" => 0)
      expect(json.to_s).not_to include("email", "address", "customer", "reference_number", "payment_proof")
    end

    it "rejects customers, unauthenticated requests, and invalid period or pagination parameters" do
      get "/admin/reports/products?from=2090-01-01&to=2090-01-01", headers: headers(user)
      expect(response).to have_http_status(:forbidden)

      get "/admin/reports/products?from=2090-01-01&to=2090-01-01"
      expect(response).to have_http_status(:unauthorized)

      admin = user(role: "admin")
      [
        [ "to=2090-01-01", "REPORT_PERIOD_REQUIRED" ],
        [ "from=2090-02-30&to=2090-03-01", "REPORT_DATE_INVALID" ],
        [ "from=2090-03-02&to=2090-03-01", "REPORT_PERIOD_INVALID" ],
        [ "from=2090-01-01&to=2091-01-02", "REPORT_PERIOD_TOO_LONG" ],
        [ "from=2090-01-01&to=2090-01-01&page=0", "REPORT_PAGINATION_INVALID" ],
        [ "from=2090-01-01&to=2090-01-01&page=1.5", "REPORT_PAGINATION_INVALID" ],
        [ "from=2090-01-01&to=2090-01-01&per_page=101", "REPORT_PAGINATION_INVALID" ]
      ].each do |query, code|
        get "/admin/reports/products?#{query}", headers: headers(admin)
        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body).dig("error", "code")).to eq(code)
      end
    end
  end

  describe "GET /admin/reports/inventory" do
    it "allows admins to view a current inventory snapshot without customer data" do
      admin = user(role: "admin")
      baseline = InventoryReportService.call(period: ReportingPeriod.new(from: "2090-01-01", to: "2090-01-02"))

      get "/admin/reports/inventory?from=2090-01-01&to=2090-01-02", headers: headers(admin)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.dig("data", "period")).to eq("from" => "2090-01-01", "to" => "2090-01-02", "timezone" => "Asia/Makassar")
      expect(json.dig("data", "totals")).to eq(baseline[:totals].stringify_keys)
      expect(json.dig("data", "products").map { |row| row["product_id"] }).to eq(baseline[:products].map { |row| row[:product_id] })
      expect(json.dig("data", "pagination")).to eq(baseline[:pagination].stringify_keys)
      expect(json.to_s).not_to include("email", "address", "customer", "phone", "reference")
    end

    it "rejects non-admin access and invalid period or pagination parameters" do
      get "/admin/reports/inventory?from=2090-01-01&to=2090-01-01", headers: headers(user)
      expect(response).to have_http_status(:forbidden)

      get "/admin/reports/inventory?from=2090-01-01&to=2090-01-01"
      expect(response).to have_http_status(:unauthorized)

      admin = user(role: "admin")
      [
        [ "from=2090-01-01", "REPORT_PERIOD_REQUIRED" ],
        [ "from=2090-02-30&to=2090-03-01", "REPORT_DATE_INVALID" ],
        [ "from=2090-03-02&to=2090-03-01", "REPORT_PERIOD_INVALID" ],
        [ "from=2090-01-01&to=2091-01-02", "REPORT_PERIOD_TOO_LONG" ],
        [ "from=2090-01-01&to=2090-01-01&page=0", "REPORT_PAGINATION_INVALID" ],
        [ "from=2090-01-01&to=2090-01-01&per_page=101", "REPORT_PAGINATION_INVALID" ]
      ].each do |query, code|
        get "/admin/reports/inventory?#{query}", headers: headers(admin)
        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body).dig("error", "code")).to eq(code)
      end
    end
  end

  describe "GET /admin/reports/:report.csv" do
    let(:export_period) { "from=2090-01-01&to=2090-01-02" }

    it "allows admins to download the three allowlisted CSV files with deterministic headers" do
      admin = user(role: "admin")
      expected = {
        "sales" => [ "sales-day-2090-01-01-to-2090-01-02.csv", %w[bucket orders_count products_quantity product_gross_amount verified_payment_amount processed_refund_amount net_receipts_amount] ],
        "orders" => [ "orders-day-2090-01-01-to-2090-01-02.csv", %w[period total_orders awaiting_payment processing shipped completed cancelled] ],
        "products" => [ "products-2090-01-01-to-2090-01-02.csv", %w[product_id name sku quantity gross_amount] ]
      }

      expected.each do |report, (filename, headers)|
        get "/admin/reports/#{report}.csv?#{export_period}", headers: headers(admin)

        expect(response).to have_http_status(:ok)
        expect(response.headers["Content-Type"]).to include("text/csv", "charset=utf-8")
        expect(response.headers["Content-Disposition"]).to include("attachment", filename)
        expect(response.body).to start_with("\uFEFF")
        expect(CSV.parse(response.body.delete_prefix("\uFEFF"), headers: true).headers).to eq(headers)
        expect(response.body).not_to match(/email|phone|address|payment_proof|reference_number/i)
      end
    end

    it "rejects unauthenticated, customer, unknown report, and invalid parameters" do
      get "/admin/reports/sales.csv?#{export_period}"
      expect(response).to have_http_status(:unauthorized)

      get "/admin/reports/sales.csv?#{export_period}", headers: headers(user)
      expect(response).to have_http_status(:forbidden)

      admin = user(role: "admin")
      get "/admin/reports/dashboard.csv?#{export_period}", headers: headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body).dig("error", "code")).to eq("REPORT_TYPE_INVALID")

      get "/admin/reports/products.csv?#{export_period}&group_by=day", headers: headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body).dig("error", "code")).to eq("REPORT_GROUP_BY_INVALID")

      get "/admin/reports/orders.csv?from=2090-02-30&to=2090-03-01", headers: headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body).dig("error", "code")).to eq("REPORT_DATE_INVALID")

      get "/admin/reports/sales.csv?#{export_period}&group_by=year", headers: headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body).dig("error", "code")).to eq("REPORT_GROUP_BY_INVALID")
    end

    it "accepts a 366-day period and rejects a 367-day period" do
      admin = user(role: "admin")
      get "/admin/reports/sales.csv?from=2090-01-01&to=2091-01-01", headers: headers(admin)
      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("sales-day-2090-01-01-to-2091-01-01.csv")

      get "/admin/reports/sales.csv?from=2090-01-01&to=2091-01-02", headers: headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body).dig("error", "code")).to eq("REPORT_PERIOD_TOO_LONG")
    end

    it "accepts month grouping for sales and orders with matching filenames" do
      admin = user(role: "admin")

      [ "sales", "orders" ].each do |report|
        get "/admin/reports/#{report}.csv?#{export_period}&group_by=month", headers: headers(admin)

        expect(response).to have_http_status(:ok)
        expect(response.headers["Content-Disposition"]).to include("#{report}-month-2090-01-01-to-2090-01-02.csv")
      end
    end

    it "rejects oversized product exports before returning an attachment" do
      admin = user(role: "admin")
      allow(ProductReportService).to receive(:export_count).and_return(10_001)

      get "/admin/reports/products.csv?#{export_period}", headers: headers(admin)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body).dig("error", "code")).to eq("export_limit_exceeded")
      expect(response.headers["Content-Disposition"]).to be_nil
    end
  end
end
