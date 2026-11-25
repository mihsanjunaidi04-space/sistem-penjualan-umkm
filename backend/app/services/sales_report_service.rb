class SalesReportService
  VERIFIED_PAYMENT_STATUSES = %w[paid refunded].freeze
  GROUPS = %w[day month].freeze
  METRIC_KEYS = %i[
    orders_count
    products_quantity
    product_gross_amount
    verified_payment_amount
    processed_refund_amount
    net_receipts_amount
  ].freeze

  class Error < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  def self.call(period:, group_by: "day")
    new(period:, group_by:).call
  end

  def initialize(period:, group_by:)
    unless GROUPS.include?(group_by)
      raise Error.new("REPORT_GROUP_BY_INVALID", "group_by harus bernilai day atau month.")
    end

    @period = period
    @group_by = group_by
  end

  def call
    orders = Order.where(created_at: time_range)
    payments = Payment.where(status: VERIFIED_PAYMENT_STATUSES, verified_at: time_range)
    refunds = Refund.where(status: "processed", processed_at: time_range)
    verified_orders = verified_payments_by_order
    items = OrderItem.joins(
      "INNER JOIN (#{verified_orders.to_sql}) verified_orders " \
      "ON verified_orders.order_id = order_items.order_id"
    )

    order_series = grouped_count(orders, bucket_expression("orders.created_at"))
    payment_series = grouped_sum(payments, bucket_expression("payments.verified_at"), :amount)
    refund_series = grouped_sum(refunds, bucket_expression("refunds.processed_at"), :amount)
    product_quantity_series = grouped_sum(items, bucket_expression("verified_orders.verified_at"), "order_items.quantity")
    product_amount_series = grouped_sum(items, bucket_expression("verified_orders.verified_at"), "order_items.subtotal")

    payment_total = payments.sum(:amount).to_i
    refund_total = refunds.sum(:amount).to_i
    totals = {
      orders_count: orders.count,
      products_quantity: items.sum("order_items.quantity").to_i,
      product_gross_amount: items.sum("order_items.subtotal").to_i,
      verified_payment_amount: payment_total,
      processed_refund_amount: refund_total,
      net_receipts_amount: payment_total - refund_total
    }

    series = bucket_keys.map do |bucket|
      payment_amount = payment_series.fetch(bucket, 0).to_i
      refund_amount = refund_series.fetch(bucket, 0).to_i
      {
        bucket: bucket,
        orders_count: order_series.fetch(bucket, 0).to_i,
        products_quantity: product_quantity_series.fetch(bucket, 0).to_i,
        product_gross_amount: product_amount_series.fetch(bucket, 0).to_i,
        verified_payment_amount: payment_amount,
        processed_refund_amount: refund_amount,
        net_receipts_amount: payment_amount - refund_amount
      }
    end

    {
      period: {
        from: @period.from_date.iso8601,
        to: @period.to_date.iso8601,
        timezone: ReportingPeriod::TIME_ZONE
      },
      group_by: @group_by,
      totals: totals,
      series: series
    }
  end

  private

  def time_range
    @period.start_at...@period.end_at
  end

  def verified_payments_by_order
    Payment.where(status: VERIFIED_PAYMENT_STATUSES, verified_at: time_range)
      .select(:order_id)
      .select("MIN(verified_at) AS verified_at")
      .group(:order_id)
  end

  def bucket_expression(column)
    format = @group_by == "day" ? "%Y-%m-%d" : "%Y-%m"
    Arel.sql("strftime('#{format}', #{column}, '+8 hours')")
  end

  def grouped_count(relation, expression)
    relation.group(expression).count.transform_keys(&:to_s)
  end

  def grouped_sum(relation, expression, column)
    relation.group(expression).sum(Arel.sql(column.to_s)).transform_keys(&:to_s)
  end

  def bucket_keys
    return day_bucket_keys if @group_by == "day"

    month_bucket_keys
  end

  def day_bucket_keys
    (@period.from_date..@period.to_date).map(&:iso8601)
  end

  def month_bucket_keys
    month = Date.new(@period.from_date.year, @period.from_date.month, 1)
    last_month = Date.new(@period.to_date.year, @period.to_date.month, 1)
    keys = []
    while month <= last_month
      keys << month.strftime("%Y-%m")
      month = month >> 1
    end
    keys
  end
end
