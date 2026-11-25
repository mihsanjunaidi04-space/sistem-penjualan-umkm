class DashboardSummaryService
  VERIFIED_PAYMENT_STATUSES = %w[paid refunded].freeze

  def self.call(period:)
    new(period:).call
  end

  def initialize(period:)
    @period = period
  end

  def call
    payments = Payment.where(status: VERIFIED_PAYMENT_STATUSES, verified_at: @period.start_at...@period.end_at)
    refunds = Refund.where(status: "processed", processed_at: @period.start_at...@period.end_at)
    sold_items = OrderItem.joins(order: :payment).where(
      payments: { status: VERIFIED_PAYMENT_STATUSES, verified_at: @period.start_at...@period.end_at }
    )
    inventory = Product.pick(
      Arel.sql("COALESCE(SUM(stock_on_hand), 0)"),
      Arel.sql("COALESCE(SUM(reserved_stock), 0)")
    ) || [ 0, 0 ]
    payment_amount = payments.sum(:amount)
    refund_amount = refunds.sum(:amount)
    stock_on_hand, reserved_stock = inventory.map(&:to_i)

    {
      period: {
        from: @period.from_date.iso8601,
        to: @period.to_date.iso8601,
        timezone: ReportingPeriod::TIME_ZONE
      },
      summary: {
        orders_created: Order.where(created_at: @period.start_at...@period.end_at).count,
        verified_payments: { count: payments.count, amount: payment_amount },
        processed_refunds: { count: refunds.count, amount: refund_amount },
        net_receipts: payment_amount - refund_amount,
        products_sold: { quantity: sold_items.sum(:quantity), gross_subtotal: sold_items.sum(:subtotal) },
        inventory: {
          stock_on_hand: stock_on_hand,
          reserved_stock: reserved_stock,
          available_stock: stock_on_hand - reserved_stock
        }
      }
    }
  end
end
