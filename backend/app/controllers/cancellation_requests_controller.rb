class CancellationRequestsController < ApplicationController
  before_action :require_customer!

  def index
    order = current_user.orders.find(params[:order_id])
    render json: { success: true, data: { cancellation_requests: order.cancellation_requests.order(created_at: :desc).map { |item| serialize(item) } }, message: "Permintaan pembatalan berhasil diambil." }
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "ORDER_NOT_FOUND", "Pesanan tidak ditemukan.")
  end

  def create
    cancellation = CancellationService.request!(order_id: params[:order_id], customer: current_user, reason: params[:reason], request: request)
    render json: { success: true, data: { cancellation_request: serialize(cancellation) }, message: "Permintaan pembatalan berhasil diajukan." }, status: :created
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "ORDER_NOT_FOUND", "Pesanan tidak ditemukan.")
  rescue CancellationService::Error => error
    render_error(:unprocessable_content, error.code, error.message)
  end

  private

  def serialize(item)
    { id: item.id, order_id: item.order_id, reason: item.reason, status: item.status, admin_note: item.admin_note, reviewed_at: item.reviewed_at&.iso8601, created_at: item.created_at.iso8601 }
  end
end
