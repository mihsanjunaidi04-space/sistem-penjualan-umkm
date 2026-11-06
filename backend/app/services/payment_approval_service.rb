class PaymentApprovalService
  class Error < StandardError
    attr_reader :code
    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  def self.approve!(payment_id:, admin:, request:)
    ActiveRecord::Base.transaction do
      payment_id_record = Payment.find(payment_id)
      order = Order.lock.find(payment_id_record.order_id)
      payment = Payment.lock.includes(:payment_proofs).find(payment_id)
      raise Error.new("INVALID_PAYMENT_STATE", "Pembayaran tidak menunggu verifikasi.") unless payment.status == "waiting_verification"
      raise Error.new("INVALID_ORDER_STATE", "Pesanan tidak dapat diproses.") unless order.status == "awaiting_payment"
      raise Error.new("CANCELLATION_PENDING", "Pembatalan pesanan sedang menunggu keputusan.") if order.cancellation_requests.where(status: "pending").exists?

      proof = payment.payment_proofs.where(status: "submitted").order(uploaded_at: :desc).first
      raise Error.new("PAYMENT_PROOF_REQUIRED", "Bukti transfer yang menunggu verifikasi tidak ditemukan.") unless proof
      raise Error.new("PAYMENT_PROOF_LATE", "Bukti transfer diunggah setelah tenggat pembayaran.") if proof.uploaded_at > order.payment_deadline_at

      reservations = order.inventory_reservations.lock.where(status: "reserved").order(:product_id).to_a
      raise Error.new("RESERVATION_INVALID", "Reservasi stok tidak valid.") if reservations.empty? || reservations.length != order.inventory_reservations.count
      products = Product.lock.where(id: reservations.map(&:product_id)).index_by(&:id)
      reservations.each { |reservation| raise Error.new("STOCK_INCONSISTENT", "Stok tidak konsisten.") unless products[reservation.product_id] && products[reservation.product_id].reserved_stock >= reservation.quantity && products[reservation.product_id].stock_on_hand >= reservation.quantity }

      now = Time.current
      reservations.each do |reservation|
        product = products.fetch(reservation.product_id)
        before = product.stock_on_hand
        Product.where(id: product.id).update_all([ "stock_on_hand = stock_on_hand - ?, reserved_stock = reserved_stock - ?, updated_at = ?", reservation.quantity, reservation.quantity, now ])
        product.reload
        reservation.update!(status: "converted", converted_at: now)
        InventoryMovement.create!(product: product, order: order, movement_type: "stock_out", quantity: -reservation.quantity, stock_before: before, stock_after: product.stock_on_hand, reference: order.order_number, notes: "Pembayaran disetujui dan reservasi dikonversi", created_by: admin)
      end
      payment.update!(status: "paid", verified_by: admin, verified_at: now, rejection_reason: nil)
      proof.update!(status: "approved", reviewed_at: now)
      order.update!(status: "processing")
      PaymentVerificationEvent.create!(payment: payment, payment_proof: proof, admin: admin, decision: "approved", created_at: now)
      AuditLog.create!(user: admin, action: "payment_approved", resource_type: "Payment", resource_id: payment.id.to_s, ip_address: request.remote_ip, user_agent: request.user_agent, metadata: { order_id: order.id, proof_id: proof.id }.to_json)
      payment
    end
  end

  def self.reject!(payment_id:, admin:, reason:, request:)
    raise Error.new("REJECTION_REASON_REQUIRED", "Alasan penolakan wajib diisi.") if reason.to_s.strip.blank?
    ActiveRecord::Base.transaction do
      payment = Payment.lock.includes(:order, :payment_proofs).find(payment_id)
      order = Order.lock.find(payment.order_id)
      raise Error.new("INVALID_PAYMENT_STATE", "Pembayaran tidak menunggu verifikasi.") unless payment.status == "waiting_verification"
      proof = payment.payment_proofs.where(status: "submitted").order(uploaded_at: :desc).first
      raise Error.new("PAYMENT_PROOF_REQUIRED", "Bukti transfer yang menunggu verifikasi tidak ditemukan.") unless proof
      now = Time.current
      payment.update!(status: "rejected", verified_by: admin, verified_at: now, rejection_reason: reason.to_s.strip.truncate(2_000))
      proof.update!(status: "rejected", reviewed_at: now)
      PaymentVerificationEvent.create!(payment: payment, payment_proof: proof, admin: admin, decision: "rejected", reason: payment.rejection_reason, created_at: now)
      AuditLog.create!(user: admin, action: "payment_rejected", resource_type: "Payment", resource_id: payment.id.to_s, ip_address: request.remote_ip, user_agent: request.user_agent, metadata: { order_id: order.id, proof_id: proof.id }.to_json)
      payment
    end
  end
end
