class Admin::PaymentsController < ApplicationController
  before_action :require_admin!

  def index
    payments = Payment.includes(:order, :payment_proofs, order: :user).where(status: params[:status].presence || "waiting_verification").order(created_at: :asc)
    render json: { success: true, data: { payments: payments.map { |payment| serialize_payment(payment) } }, message: "Pembayaran berhasil diambil." }
  end

  def show
    render json: { success: true, data: { payment: serialize_payment(Payment.includes(:order, :payment_proofs, :verification_events).find(params[:id])) }, message: "Detail pembayaran berhasil diambil." }
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "PAYMENT_NOT_FOUND", "Pembayaran tidak ditemukan.")
  end

  def proof
    payment = Payment.joins(:order).where(orders: { user_id: User.where(role: "customer").select(:id) }).find(params[:id])
    proof = payment.payment_proofs.find(params[:proof_id])
    file = PrivatePaymentProofStorage.open(proof.storage_key)
    send_verified_file(file, type: proof.mime_type, disposition: "inline", filename: "payment-proof-#{proof.id}#{payment_proof_extension(proof.mime_type)}")
  rescue ActiveRecord::RecordNotFound, ArgumentError
    render_error(:not_found, "PAYMENT_PROOF_NOT_FOUND", "Bukti pembayaran tidak ditemukan.")
  end

  def approve
    payment = PaymentApprovalService.approve!(payment_id: params[:id], admin: current_user, request: request)
    render json: { success: true, data: { payment: serialize_payment(payment) }, message: "Pembayaran disetujui." }
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "PAYMENT_NOT_FOUND", "Pembayaran tidak ditemukan.")
  rescue PaymentApprovalService::Error => error
    render_error(:unprocessable_content, error.code, error.message)
  end

  def reject
    payment = PaymentApprovalService.reject!(payment_id: params[:id], admin: current_user, reason: params[:reason], request: request)
    render json: { success: true, data: { payment: serialize_payment(payment) }, message: "Pembayaran ditolak." }
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "PAYMENT_NOT_FOUND", "Pembayaran tidak ditemukan.")
  rescue PaymentApprovalService::Error => error
    render_error(:unprocessable_content, error.code, error.message)
  end

  def settings
    keys = %w[bank_name bank_account_name bank_account_number bank_transfer_instructions]
    values = StoreSetting.where(setting_key: keys).index_by(&:setting_key)
    render json: { success: true, data: { settings: keys.index_with { |key| values[key]&.setting_value } }, message: "Pengaturan pembayaran berhasil diambil." }
  end

  def update_settings
    permitted = params.permit(:bank_name, :bank_account_name, :bank_account_number, :bank_transfer_instructions)
    ActiveRecord::Base.transaction { permitted.each { |key, value| StoreSetting.find_or_initialize_by(setting_key: key).update!(setting_value: value.to_s.strip, updated_by: current_user) } }
    settings
  rescue ActiveRecord::RecordInvalid => error
    render_error(:unprocessable_content, "VALIDATION_ERROR", "Pengaturan tidak valid.", error.record.errors.to_hash)
  end

  private

  def serialize_payment(payment)
    order = payment.order
    { id: payment.id, amount: payment.amount, method: payment.payment_method, status: payment.status, rejection_reason: payment.rejection_reason, verified_at: payment.verified_at&.iso8601, order: { id: order.id, order_number: order.order_number, status: order.status, total_amount: order.total_amount, customer_name: order.user.name, payment_deadline_at: order.payment_deadline_at.iso8601 }, proofs: payment.payment_proofs.order(created_at: :desc).map { |proof| { id: proof.id, status: proof.status, original_filename: proof.original_filename, mime_type: proof.mime_type, file_size: proof.file_size, uploaded_at: proof.uploaded_at.iso8601, url: "/admin/payments/#{payment.id}/proofs/#{proof.id}" } }, verification_history: payment.respond_to?(:verification_events) ? payment.verification_events.includes(:admin).order(created_at: :desc).map { |event| { decision: event.decision, reason: event.reason, admin_name: event.admin.name, created_at: event.created_at.iso8601 } } : [] }
  end

  def payment_proof_extension(mime_type)
    { "image/jpeg" => ".jpg", "image/png" => ".png", "image/webp" => ".webp" }.fetch(mime_type, ".bin")
  end

  def send_verified_file(file, **options)
    response.headers["Content-Length"] = file.size.to_s
    send_data file, **options
  rescue StandardError
    file.close
    raise
  end
end
