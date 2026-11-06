class Admin::CancellationRequestsController < ApplicationController
  before_action :require_admin!

  def index
    requests = CancellationRequest.includes(:order, :requested_by).where(status: params[:status].presence || "pending").order(created_at: :asc)
    render json: { success: true, data: { cancellation_requests: requests.map { |item| serialize(item) } }, message: "Permintaan pembatalan berhasil diambil." }
  end

  def approve
    render_decision("Pembatalan disetujui.") { CancellationService.approve!(id: params[:id], admin: current_user, request: request) }
  end

  def reject
    render_decision("Pembatalan ditolak.") { CancellationService.reject!(id: params[:id], admin: current_user, note: params[:admin_note], request: request) }
  end

  private

  def render_decision(message)
    item = yield
    render json: { success: true, data: { cancellation_request: serialize(item) }, message: message }
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "CANCELLATION_NOT_FOUND", "Permintaan pembatalan tidak ditemukan.")
  rescue CancellationService::Error => error
    render_error(:unprocessable_content, error.code, error.message)
  end

  def serialize(item)
    { id: item.id, order_id: item.order_id, order_number: item.order.order_number, customer_name: item.requested_by.name, reason: item.reason, status: item.status, admin_note: item.admin_note, reviewed_at: item.reviewed_at&.iso8601, created_at: item.created_at.iso8601 }
  end
end
