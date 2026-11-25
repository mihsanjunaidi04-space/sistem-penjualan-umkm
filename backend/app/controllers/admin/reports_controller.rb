class Admin::ReportsController < ApplicationController
  before_action :require_admin!

  def dashboard
    period = ReportingPeriod.new(from: params[:from], to: params[:to])
    data = DashboardSummaryService.call(period:)
    render json: { success: true, data: data, message: "Ringkasan dashboard berhasil diambil." }
  rescue ReportingPeriod::Error => error
    render_error(:unprocessable_content, error.code, error.message, error.details)
  end

  def sales
    period = ReportingPeriod.new(from: params[:from], to: params[:to])
    group_by = params.key?(:group_by) ? params[:group_by] : "day"
    data = SalesReportService.call(period:, group_by:)
    render json: { success: true, data: data, message: "Laporan penjualan berhasil diambil." }
  rescue ReportingPeriod::Error, SalesReportService::Error => error
    render_error(:unprocessable_content, error.code, error.message, error.respond_to?(:details) ? error.details : {})
  end

  def orders
    period = ReportingPeriod.new(from: params[:from], to: params[:to])
    group_by = params.key?(:group_by) ? params[:group_by] : "day"
    data = OrderReportService.call(period:, group_by:)
    render json: { success: true, data: data, message: "Laporan pesanan berhasil diambil." }
  rescue ReportingPeriod::Error, OrderReportService::Error => error
    render_error(:unprocessable_content, error.code, error.message, error.respond_to?(:details) ? error.details : {})
  end

  def products
    period = ReportingPeriod.new(from: params[:from], to: params[:to])
    data = ProductReportService.call(period:, page: params[:page], per_page: params[:per_page])
    render json: { success: true, data: data, message: "Laporan produk berhasil diambil." }
  rescue ReportingPeriod::Error, ProductReportService::Error => error
    render_error(:unprocessable_content, error.code, error.message, error.respond_to?(:details) ? error.details : {})
  end

  def inventory
    period = ReportingPeriod.new(from: params[:from], to: params[:to])
    data = InventoryReportService.call(period:, page: params[:page], per_page: params[:per_page])
    render json: { success: true, data: data, message: "Laporan inventory berhasil diambil." }
  rescue ReportingPeriod::Error, InventoryReportService::Error => error
    render_error(:unprocessable_content, error.code, error.message, error.respond_to?(:details) ? error.details : {})
  end

  def export
    period = ReportingPeriod.new(from: params[:from], to: params[:to])
    group_by = params.key?(:group_by) ? params[:group_by] : nil
    file = ReportCsvExportService.call(report: params[:report], period:, group_by:)
    send_data file.body,
      filename: file.filename,
      type: "text/csv; charset=utf-8",
      disposition: "attachment"
  rescue ReportingPeriod::Error, ReportCsvExportService::Error, SalesReportService::Error, OrderReportService::Error => error
    render_error(:unprocessable_content, error.code, error.message, error.respond_to?(:details) ? error.details : {})
  end
end
