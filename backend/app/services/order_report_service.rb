class OrderReportService
  ORDER_STATUSES = %w[awaiting_payment processing shipped completed cancelled].freeze
  GROUPS = %w[day month].freeze

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
    orders = Order.where(created_at: @period.start_at...@period.end_at)
    status_counts = orders.group(:status).count
    grouped_counts = orders.group(bucket_expression, :status).count

    totals_by_status = status_counts_for(ORDER_STATUSES, status_counts)
    total_orders = totals_by_status.values.sum
    series = bucket_keys.map do |period_key|
      by_status = ORDER_STATUSES.index_with { 0 }
      ORDER_STATUSES.each do |status|
        by_status[status] = grouped_counts.fetch([ period_key, status ], 0).to_i
      end

      { period: period_key, total_orders: by_status.values.sum, by_status: by_status }
    end

    {
      period: {
        from: @period.from_date.iso8601,
        to: @period.to_date.iso8601,
        timezone: ReportingPeriod::TIME_ZONE
      },
      group_by: @group_by,
      totals: { total_orders: total_orders, by_status: totals_by_status },
      series: series
    }
  end

  private

  def status_counts_for(statuses, counts)
    statuses.index_with { |status| counts.fetch(status, 0).to_i }
  end

  def bucket_expression
    format = @group_by == "day" ? "%Y-%m-%d" : "%Y-%m"
    Arel.sql("strftime('#{format}', orders.created_at, '+8 hours')")
  end

  def bucket_keys
    return (@period.from_date..@period.to_date).map(&:iso8601) if @group_by == "day"

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
