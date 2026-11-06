class PaymentsController < ApplicationController
  before_action :require_customer!

  def upload_proof
    order = current_user.orders.includes(:payment).find(params[:order_id])
    payment = order.payment
    return render_error(:unprocessable_content, "PAYMENT_UNAVAILABLE", "Pembayaran tidak dapat diunggah untuk pesanan ini.") unless payment && %w[pending rejected].include?(payment.status) && order.status == "awaiting_payment"
    return render_error(:conflict, "CANCELLATION_PENDING", "Pembatalan pesanan sedang menunggu keputusan.") if order.cancellation_requests.where(status: "pending").exists?
    return render_error(:unprocessable_content, "PAYMENT_DEADLINE_PASSED", "Tenggat pembayaran telah lewat.") if order.payment_deadline_at <= Time.current

    proof = ActiveRecord::Base.transaction do
      proof = PaymentProofUploadService.call(payment: payment, upload: params[:proof])
      payment.update!(status: "waiting_verification", rejection_reason: nil)
      proof
    end
    render json: { success: true, data: { payment: serialize_payment(payment.reload) }, message: "Bukti transfer berhasil diunggah dan menunggu verifikasi." }, status: :created
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "ORDER_NOT_FOUND", "Pesanan tidak ditemukan.")
  rescue PaymentProofUploadService::Error => error
    render_error(:unprocessable_content, error.code, error.message)
  end

  def proof
    order = current_user.orders.find(params[:order_id])
    proof = order.payment.payment_proofs.find(params[:proof_id])
    send_file PrivatePaymentProofStorage.path(proof.storage_key), type: proof.mime_type, disposition: "inline", filename: "payment-proof-#{proof.id}#{File.extname(proof.original_filename).downcase}"
  rescue ActiveRecord::RecordNotFound, ArgumentError
    render_error(:not_found, "PAYMENT_PROOF_NOT_FOUND", "Bukti pembayaran tidak ditemukan.")
  end

  private

  def serialize_payment(payment)
    { id: payment.id, amount: payment.amount, method: payment.payment_method, status: payment.status, rejection_reason: payment.rejection_reason, verified_at: payment.verified_at&.iso8601, proofs: payment.payment_proofs.order(created_at: :desc).map { |proof| { id: proof.id, status: proof.status, original_filename: proof.original_filename, uploaded_at: proof.uploaded_at.iso8601 } } }
  end
end
