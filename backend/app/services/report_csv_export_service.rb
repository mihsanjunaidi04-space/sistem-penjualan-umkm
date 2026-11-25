require "csv"

class ReportCsvExportService
  REPORTS = %w[sales orders products].freeze
  MAX_ROWS = 10_000
  CSV_HEADERS = {
    "sales" => %w[bucket orders_count products_quantity product_gross_amount verified_payment_amount processed_refund_amount net_receipts_amount].freeze,
    "orders" => %w[period total_orders awaiting_payment processing shipped completed cancelled].freeze,
    "products" => %w[product_id name sku quantity gross_amount].freeze
  }.freeze

  Export = Data.define(:filename, :body)

  class Error < StandardError
    attr_reader :code, :details

    def initialize(code, message, details = {})
      @code = code
      @details = details
      super(message)
    end
  end

  def self.call(report:, period:, group_by: nil)
    new(report:, period:, group_by:).call
  end

  def initialize(report:, period:, group_by: nil)
    unless REPORTS.include?(report)
      raise Error.new("REPORT_TYPE_INVALID", "Jenis laporan tidak tersedia untuk ekspor.", { report: "tidak valid" })
    end

    if report == "products" && !group_by.nil?
      raise Error.new("REPORT_GROUP_BY_INVALID", "group_by tidak berlaku untuk laporan produk.", { group_by: "tidak berlaku" })
    end

    @report = report
    @period = period
    @group_by = group_by || "day"
  end

  def call
    rows = report_rows
    ensure_within_limit!(rows.length) unless @report == "products"

    csv = CSV.generate(encoding: Encoding::UTF_8, row_sep: "\r\n") do |writer|
      writer << CSV_HEADERS.fetch(@report)
      if @report == "products"
        ProductReportService.each_export_batch(period: @period) do |product|
          ensure_within_limit!(@product_rows_written.to_i + 1)
          @product_rows_written = @product_rows_written.to_i + 1
          writer << [ product[:product_id], safe_text(product[:name]), safe_text(product[:sku]), product[:quantity], product[:gross_amount] ]
        end
      else
        rows.each { |row| writer << row }
      end
    end

    Export.new(filename: filename, body: "\uFEFF#{csv}")
  end

  private

  def report_rows
    case @report
    when "sales"
      data = SalesReportService.call(period: @period, group_by: @group_by)
      ensure_within_limit!(data.fetch(:series).length)
      data.fetch(:series).map do |row|
        CSV_HEADERS.fetch("sales").map { |key| row.fetch(key.to_sym) }
      end
    when "orders"
      data = OrderReportService.call(period: @period, group_by: @group_by)
      ensure_within_limit!(data.fetch(:series).length)
      data.fetch(:series).map do |row|
        status_counts = row.fetch(:by_status)
        [ row.fetch(:period), row.fetch(:total_orders), *OrderReportService::ORDER_STATUSES.map { |status| status_counts.fetch(status) } ]
      end
    when "products"
      ensure_within_limit!(ProductReportService.export_count(period: @period))
      []
    end
  end

  def ensure_within_limit!(count)
    return if count <= MAX_ROWS

    raise Error.new("export_limit_exceeded", "Ekspor melebihi batas maksimal #{MAX_ROWS} baris data.", { max_rows: MAX_ROWS })
  end

  def filename
    base = @report
    base = "#{base}-#{@group_by}" unless @report == "products"
    "#{base}-#{@period.from_date.iso8601}-to-#{@period.to_date.iso8601}.csv"
  end

  def safe_text(value)
    text = value.to_s
    text.match?(/\A[=+\-@\t\r\n]/) ? "'#{text}" : text
  end
end
