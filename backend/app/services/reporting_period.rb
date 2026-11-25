class ReportingPeriod
  TIME_ZONE = "Asia/Makassar"
  MAX_DAYS = 366

  class Error < StandardError
    attr_reader :code, :details

    def initialize(code, message, details = {})
      @code = code
      @details = details
      super(message)
    end
  end

  attr_reader :from_date, :to_date, :start_at, :end_at

  def initialize(from:, to:)
    @from_date = parse_date(from, "from")
    @to_date = parse_date(to, "to")
    raise Error.new("REPORT_PERIOD_INVALID", "Tanggal awal tidak boleh setelah tanggal akhir.") if from_date > to_date

    days = (to_date - from_date).to_i + 1
    raise Error.new("REPORT_PERIOD_TOO_LONG", "Rentang laporan maksimal #{MAX_DAYS} hari.") if days > MAX_DAYS

    zone = ActiveSupport::TimeZone[TIME_ZONE]
    @start_at = zone.local(from_date.year, from_date.month, from_date.day).utc
    next_day = to_date + 1
    @end_at = zone.local(next_day.year, next_day.month, next_day.day).utc
  end

  private

  def parse_date(value, name)
    if value.blank?
      raise Error.new("REPORT_PERIOD_REQUIRED", "Parameter from dan to wajib diisi.", { name => "wajib diisi" })
    end

    unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      raise Error.new("REPORT_DATE_INVALID", "Tanggal harus menggunakan format YYYY-MM-DD.", { name => "format tidak valid" })
    end

    date = Date.iso8601(value)
    raise ArgumentError unless date.iso8601 == value

    date
  rescue Date::Error, ArgumentError
    raise Error.new("REPORT_DATE_INVALID", "Tanggal tidak valid.", { name => "tanggal tidak valid" })
  end
end
