class CancellationService
  class Error < StandardError
    attr_reader :code
    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  ELIGIBLE_PAYMENT_STATES = %w[pending rejected waiting_verification].freeze

  def self.request!(order_id:, customer:, reason:, request:)
    raise Error.new("REASON_REQUIRED", "Alasan pembatalan wajib diisi.") if reason.to_s.strip.blank?
    ActiveRecord::Base.transaction do
      order = customer.orders.lock.find(order_id)
      payment = Payment.lock.find_by(order_id: order.id)
      raise Error.new("CANCELLATION_NOT_ALLOWED", "Pesanan tidak dapat dibatalkan pada status saat ini.") unless order.status == "awaiting_payment" && payment && ELIGIBLE_PAYMENT_STATES.include?(payment.status) && order.payment_deadline_at > Time.current
      raise Error.new("CANCELLATION_ALREADY_PENDING", "Permintaan pembatalan sedang diproses.") if order.cancellation_requests.where(status: "pending").exists?

      cancellation = order.cancellation_requests.create!(requested_by: customer, reason: reason.to_s.strip.truncate(2_000), status: "pending")
      AuditLog.create!(user: customer, action: "cancellation_requested", resource_type: "CancellationRequest", resource_id: cancellation.id.to_s, ip_address: request.remote_ip, user_agent: request.user_agent, metadata: { order_id: order.id }.to_json)
      cancellation
    end
  rescue ActiveRecord::RecordNotFound
    raise Error.new("ORDER_NOT_FOUND", "Pesanan tidak ditemukan.")
  end

  def self.approve!(id:, admin:, request:)
    ActiveRecord::Base.transaction do
      cancellation = CancellationRequest.lock.find(id)
      order = Order.lock.find(cancellation.order_id)
      payment = Payment.lock.find_by(order_id: order.id)
      raise Error.new("INVALID_CANCELLATION_STATE", "Permintaan pembatalan tidak lagi menunggu keputusan.") unless cancellation.status == "pending"
      raise Error.new("CANCELLATION_NOT_ALLOWED", "Pesanan tidak lagi dapat dibatalkan.") unless order.status == "awaiting_payment" && payment && ELIGIBLE_PAYMENT_STATES.include?(payment.status)

      release_reservations!(order, admin)
      now = Time.current
      cancellation.update!(status: "approved", reviewed_by: admin, reviewed_at: now)
      order.update!(status: "cancelled", cancelled_at: now)
      if payment.status == "waiting_verification"
        payment.update!(status: "rejected", rejection_reason: "Pesanan dibatalkan sebelum pembayaran disetujui.", verified_by: admin, verified_at: now)
        payment.payment_proofs.where(status: "submitted").update_all(status: "rejected", reviewed_at: now, updated_at: now)
      end
      AuditLog.create!(user: admin, action: "cancellation_approved", resource_type: "CancellationRequest", resource_id: cancellation.id.to_s, ip_address: request.remote_ip, user_agent: request.user_agent, metadata: { order_id: order.id }.to_json)
      cancellation
    end
  end

  def self.reject!(id:, admin:, note:, request:)
    raise Error.new("ADMIN_NOTE_REQUIRED", "Catatan penolakan wajib diisi.") if note.to_s.strip.blank?
    ActiveRecord::Base.transaction do
      cancellation = CancellationRequest.lock.find(id)
      order = Order.lock.find(cancellation.order_id)
      raise Error.new("INVALID_CANCELLATION_STATE", "Permintaan pembatalan tidak lagi menunggu keputusan.") unless cancellation.status == "pending"
      raise Error.new("CANCELLATION_NOT_ALLOWED", "Pesanan tidak lagi dapat diproses.") unless order.status == "awaiting_payment"
      now = Time.current
      cancellation.update!(status: "rejected", reviewed_by: admin, reviewed_at: now, admin_note: note.to_s.strip.truncate(2_000))
      AuditLog.create!(user: admin, action: "cancellation_rejected", resource_type: "CancellationRequest", resource_id: cancellation.id.to_s, ip_address: request.remote_ip, user_agent: request.user_agent, metadata: { order_id: order.id }.to_json)
      cancellation
    end
  end

  def self.release_reservations!(order, admin)
    reservations = order.inventory_reservations.lock.where(status: "reserved").order(:product_id).to_a
    products = Product.lock.where(id: reservations.map(&:product_id)).index_by(&:id)
    now = Time.current
    reservations.each do |reservation|
      product = products[reservation.product_id]
      raise Error.new("RESERVATION_INVALID", "Reservasi stok tidak konsisten.") unless product && product.reserved_stock >= reservation.quantity
      before = product.stock_on_hand - product.reserved_stock
      Product.where(id: product.id).update_all(["reserved_stock = reserved_stock - ?, updated_at = ?", reservation.quantity, now])
      product.reload
      reservation.update!(status: "released", released_at: now)
      InventoryMovement.create!(product: product, order: order, movement_type: "reservation_release", quantity: reservation.quantity, stock_before: before, stock_after: product.stock_on_hand - product.reserved_stock, reference: order.order_number, notes: "Reservasi dilepas karena pembatalan disetujui", created_by: admin)
    end
  end
end
