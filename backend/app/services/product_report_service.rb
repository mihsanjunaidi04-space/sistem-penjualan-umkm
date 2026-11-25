class ProductReportService
  VERIFIED_PAYMENT_STATUSES = %w[paid refunded].freeze
  DEFAULT_PAGE = 1
  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 100
  EXPORT_BATCH_SIZE = 500

  class Error < StandardError
    attr_reader :code, :details

    def initialize(code, message, details = {})
      @code = code
      @details = details
      super(message)
    end
  end

  def self.call(period:, page: nil, per_page: nil)
    new(period:, page:, per_page:).call
  end

  def self.export_count(period:)
    new(period:).export_count
  end

  def self.each_export_batch(period:, &block)
    new(period:).each_export_batch(&block)
  end

  def initialize(period:, page: nil, per_page: nil)
    @period = period
    @page = parse_integer(page, "page", DEFAULT_PAGE, minimum: 1)
    @per_page = parse_integer(per_page, "per_page", DEFAULT_PER_PAGE, minimum: 1, maximum: MAX_PER_PAGE)
  end

  def call
    sales = sales_scope

    total_count = sales.distinct.count("products.id")
    total_quantity = sales.sum("order_items.quantity").to_i
    gross_product_amount = sales.sum("order_items.subtotal").to_i
    processed_refund_amount = Refund.where(status: "processed", processed_at: time_range).sum(:amount).to_i

    products = product_rows(sales)
      .offset((@page - 1) * @per_page)
      .limit(@per_page)
      .map { |product| serialize_product(product) }

    {
      period: {
        from: @period.from_date.iso8601,
        to: @period.to_date.iso8601,
        timezone: ReportingPeriod::TIME_ZONE
      },
      totals: {
        total_quantity: total_quantity,
        gross_product_amount: gross_product_amount,
        processed_refund_amount: processed_refund_amount,
        total_products_sold: total_count
      },
      products: products,
      pagination: {
        page: @page,
        per_page: @per_page,
        total_count: total_count,
        total_pages: (total_count + @per_page - 1) / @per_page
      }
    }
  end

  def export_count
    sales_scope.distinct.count("products.id")
  end

  def each_export_batch
    return enum_for(__method__) unless block_given?

    offset = 0
    loop do
      rows = product_rows(sales_scope)
        .offset(offset)
        .limit(EXPORT_BATCH_SIZE)
        .map { |product| serialize_product(product) }
      break if rows.empty?

      rows.each { |row| yield row }
      offset += rows.length
    end
  end

  private

  def sales_scope
    Product.joins(order_items: { order: :payment })
      .where(payments: { status: VERIFIED_PAYMENT_STATUSES, verified_at: time_range })
  end

  def product_rows(sales)
    sales.group("products.id")
      .select(
        "products.id AS product_id, products.name AS name, products.sku AS sku, " \
        "SUM(order_items.quantity) AS quantity, SUM(order_items.subtotal) AS gross_amount"
      )
      .order(Arel.sql("gross_amount DESC, products.id ASC"))
  end

  def serialize_product(product)
    {
      product_id: product[:product_id].to_i,
      name: product[:name],
      sku: product[:sku],
      quantity: product[:quantity].to_i,
      gross_amount: product[:gross_amount].to_i
    }
  end

  def time_range
    @period.start_at...@period.end_at
  end

  def parse_integer(value, name, default, minimum:, maximum: nil)
    return default if value.nil?

    parsed = if value.is_a?(Integer)
      value
    elsif value.is_a?(String) && value.match?(/\A\d+\z/)
      value.to_i
    end

    if parsed.nil? || parsed < minimum || (maximum && parsed > maximum)
      constraint = maximum ? "#{minimum} sampai #{maximum}" : "minimal #{minimum}"
      raise Error.new("REPORT_PAGINATION_INVALID", "Parameter #{name} harus berupa bilangan bulat #{constraint}.", { name => "tidak valid" })
    end

    parsed
  end
end
