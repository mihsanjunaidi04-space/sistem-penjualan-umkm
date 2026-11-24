class Admin::RefundsController < ApplicationController
  before_action :require_admin!

  def index
    refunds = Refund.includes(:payment, :order, :processed_by).order(created_at: :desc)
    if params[:status].present?
      return render_error(:unprocessable_content, "REFUND_STATUS_INVALID", "Status refund tidak valid.") unless Refund::STATUSES.include?(params[:status])

      refunds = refunds.where(status: params[:status])
    end
    render json: { success: true, data: { refunds: refunds.map { |refund| serialize_refund(refund) } }, message: "Refund berhasil diambil." }
  end

  def show
    refund = Refund.includes(:payment, :order, :processed_by).find(params[:id])
    render json: { success: true, data: { refund: serialize_refund(refund) }, message: "Detail refund berhasil diambil." }
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "REFUND_NOT_FOUND", "Refund tidak ditemukan.")
  end

  def create
    key = request.headers["Idempotency-Key"].to_s.strip
    if key.blank?
      return render_error(:bad_request, "IDEMPOTENCY_KEY_REQUIRED", "Header Idempotency-Key wajib diisi.")
    end
    if key.length > 180
      return render_error(:bad_request, "IDEMPOTENCY_KEY_INVALID", "Idempotency-Key maksimal 180 karakter.")
    end

    refund = RefundService.create!(payment_id: params[:payment_id], idempotency_key: key, amount: refund_params[:amount], reason: refund_params[:reason], admin: current_user, request: request)
    render json: { success: true, data: { refund: serialize_refund(refund) }, message: "Refund pending berhasil dibuat." }, status: :created
  rescue RefundService::Conflict => error
    render_error(:conflict, error.code, error.message)
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "PAYMENT_NOT_FOUND", "Payment tidak ditemukan.")
  rescue RefundService::Error => error
    render_error(:unprocessable_content, error.code, error.message)
  rescue ActiveRecord::RecordInvalid => error
    render_error(:unprocessable_content, "VALIDATION_ERROR", "Refund tidak valid.", error.record.errors.to_hash)
  end

  def mark_processed
    refund = RefundService.process!(id: params[:id], reference_number: transition_params[:reference_number], notes: transition_params[:notes], admin: current_user, request: request)
    render json: { success: true, data: { refund: serialize_refund(refund) }, message: "Refund ditandai processed setelah konfirmasi transfer." }
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "REFUND_NOT_FOUND", "Refund tidak ditemukan.")
  rescue RefundService::Error => error
    render_error(:unprocessable_content, error.code, error.message)
  rescue ActiveRecord::RecordInvalid => error
    render_error(:unprocessable_content, "VALIDATION_ERROR", "Refund tidak valid.", error.record.errors.to_hash)
  end

  def reject
    refund = RefundService.reject!(id: params[:id], notes: transition_params[:notes], admin: current_user, request: request)
    render json: { success: true, data: { refund: serialize_refund(refund) }, message: "Refund ditolak." }
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "REFUND_NOT_FOUND", "Refund tidak ditemukan.")
  rescue RefundService::Error => error
    render_error(:unprocessable_content, error.code, error.message)
  rescue ActiveRecord::RecordInvalid => error
    render_error(:unprocessable_content, "VALIDATION_ERROR", "Refund tidak valid.", error.record.errors.to_hash)
  end

  private

  def refund_params
    params.require(:refund).permit(:amount, :reason)
  end

  def transition_params
    params.require(:refund).permit(:reference_number, :notes)
  end

  def serialize_refund(refund)
    {
      id: refund.id,
      payment_id: refund.payment_id,
      order_id: refund.order_id,
      amount: refund.amount,
      reason: refund.reason,
      status: refund.status,
      processed_by: refund.processed_by&.name,
      processed_at: refund.processed_at&.iso8601,
      reference_number: refund.reference_number,
      notes: refund.notes,
      created_at: refund.created_at.iso8601
    }
  end
end
