class InventoryReportService
  DEFAULT_PAGE = 1
  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 100
  PHYSICAL_MOVEMENT_TYPES = %w[stock_in stock_out].freeze

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

  def initialize(period:, page: nil, per_page: nil)
    @period = period
    @page = parse_integer(page, "page", DEFAULT_PAGE, minimum: 1)
    @per_page = parse_integer(per_page, "per_page", DEFAULT_PER_PAGE, minimum: 1, maximum: MAX_PER_PAGE)
  end

  def call
    products = products_scope
    total_count = products.count
    stock_on_hand, reserved_stock = products.pick(
      Arel.sql("COALESCE(SUM(products.stock_on_hand), 0)"),
      Arel.sql("COALESCE(SUM(products.reserved_stock), 0)")
    ) || [ 0, 0 ]
    stock_in_quantity, stock_out_quantity = movement_totals

    page_products = products.order(:id)
      .offset((@page - 1) * @per_page)
      .limit(@per_page)
      .select(:id, :name, :sku, :is_active, :stock_on_hand, :reserved_stock)
      .to_a
    movement_by_product = movements_for(page_products.map(&:id)).group(:product_id).pluck(
      :product_id,
      Arel.sql("COALESCE(SUM(CASE WHEN movement_type = 'stock_in' THEN ABS(quantity) ELSE 0 END), 0)"),
      Arel.sql("COALESCE(SUM(CASE WHEN movement_type = 'stock_out' THEN ABS(quantity) ELSE 0 END), 0)")
    ).to_h do |product_id, stock_in, stock_out|
      [ product_id, { stock_in_quantity: stock_in.to_i, stock_out_quantity: stock_out.to_i } ]
    end

    {
      period: {
        from: @period.from_date.iso8601,
        to: @period.to_date.iso8601,
        timezone: ReportingPeriod::TIME_ZONE
      },
      totals: {
        total_products: total_count,
        stock_on_hand: stock_on_hand.to_i,
        reserved_stock: reserved_stock.to_i,
        available_stock: stock_on_hand.to_i - reserved_stock.to_i,
        stock_in_quantity: stock_in_quantity,
        stock_out_quantity: stock_out_quantity
      },
      products: page_products.map do |product|
        movements = movement_by_product.fetch(product.id, { stock_in_quantity: 0, stock_out_quantity: 0 })
        {
          product_id: product.id,
          name: product.name,
          sku: product.sku,
          is_active: product.is_active,
          stock_on_hand: product.stock_on_hand,
          reserved_stock: product.reserved_stock,
          available_stock: product.stock_on_hand - product.reserved_stock,
          stock_in_quantity: movements[:stock_in_quantity],
          stock_out_quantity: movements[:stock_out_quantity]
        }
      end,
      pagination: {
        page: @page,
        per_page: @per_page,
        total_count: total_count,
        total_pages: (total_count + @per_page - 1) / @per_page
      }
    }
  end

  private

  def products_scope
    period_movement_product_ids = InventoryMovement.where(
      movement_type: PHYSICAL_MOVEMENT_TYPES,
      created_at: time_range
    ).select(:product_id)

    Product.where("products.stock_on_hand > 0 OR products.reserved_stock > 0")
      .or(Product.where(id: period_movement_product_ids))
  end

  def movement_scope
    InventoryMovement.where(movement_type: PHYSICAL_MOVEMENT_TYPES, created_at: time_range)
  end

  def movement_totals
    movement_scope.pick(
      Arel.sql("COALESCE(SUM(CASE WHEN movement_type = 'stock_in' THEN ABS(quantity) ELSE 0 END), 0)"),
      Arel.sql("COALESCE(SUM(CASE WHEN movement_type = 'stock_out' THEN ABS(quantity) ELSE 0 END), 0)")
    ).map(&:to_i)
  end

  def movements_for(product_ids)
    return InventoryMovement.none if product_ids.empty?

    movement_scope.where(product_id: product_ids)
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
