require "digest"
require "json"

class RefundService
  class Error < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  class Conflict < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  class IdempotencyClaimConflict < StandardError
    attr_reader :original_error

    def initialize(original_error)
      @original_error = original_error
      super(original_error.message)
    end
  end

  REFUNDABLE_STATUSES = %w[pending processed].freeze
  MAX_REASON_LENGTH = 2_000
  MAX_NOTES_LENGTH = 2_000
  MAX_REFERENCE_LENGTH = 80

  def self.create!(payment_id:, idempotency_key:, amount:, reason:, admin:, request:)
    new(admin:, request:).create!(payment_id:, idempotency_key:, amount:, reason:)
  end

  def self.process!(id:, reference_number:, notes:, admin:, request:)
    new(admin:, request:).process!(id:, reference_number:, notes:)
  end

  def self.reject!(id:, notes:, admin:, request:)
    new(admin:, request:).reject!(id:, notes:)
  end

  def initialize(admin:, request:)
    @admin = admin
    @request = request
    raise Error.new("ADMIN_REQUIRED", "Refund hanya dapat dikelola admin.") unless @admin&.admin?
  end

  def create!(payment_id:, idempotency_key:, amount:, reason:)
    normalized_key = normalize_idempotency_key(idempotency_key)
    normalized_amount = normalize_amount(amount)
    normalized_reason = reason.to_s.strip
    raise Error.new("REFUND_REASON_REQUIRED", "Alasan refund wajib diisi.") if normalized_reason.blank?
    normalized_reason = normalized_reason.truncate(MAX_REASON_LENGTH)

    begin
      ActiveRecord::Base.transaction(requires_new: true) do
        payment = Payment.find(payment_id)
        request_hash = request_fingerprint(payment.id, normalized_amount, normalized_reason)
        idempotency_record = RefundIdempotencyKey.find_by(admin_id: @admin.id, payment_id: payment.id, key: normalized_key)
        if idempotency_record
          raise_payload_conflict! unless idempotency_record.request_hash == request_hash

          next refund_from_idempotency_record!(idempotency_record, payment)
        end

        raise Error.new("REFUND_PAYMENT_NOT_PAID", "Refund hanya dapat dibuat untuk payment berstatus paid.") unless payment.status == "paid"

        order = payment.order
        reserved_amount = payment.refunds.where(status: REFUNDABLE_STATUSES).sum(:amount)
        if reserved_amount + normalized_amount > payment.amount
          raise Error.new("REFUND_LIMIT_EXCEEDED", "Total refund pending dan processed melebihi jumlah payment yang diterima.")
        end

        refund = Refund.create!(payment: payment, order: order, amount: normalized_amount, reason: normalized_reason, status: "pending")
        persist_idempotency_key!(admin: @admin, payment:, refund:, key: normalized_key, request_hash: request_hash)
        audit!("refund_created", refund, { payment_id: payment.id, order_id: order.id, amount: refund.amount, status: refund.status })
        refund
      end
    rescue IdempotencyClaimConflict => error
      resolve_idempotency_claim!(payment_id:, key: normalized_key, request_hash: request_fingerprint(payment_id, normalized_amount, normalized_reason), original_error: error.original_error)
    end
  end

  def process!(id:, reference_number:, notes:)
    normalized_reference = reference_number.to_s.strip
    raise Error.new("REFUND_REFERENCE_REQUIRED", "Referensi transfer wajib diisi.") if normalized_reference.blank?
    if normalized_reference.length > MAX_REFERENCE_LENGTH
      raise Error.new("REFUND_REFERENCE_INVALID", "Referensi transfer maksimal #{MAX_REFERENCE_LENGTH} karakter.")
    end

    ActiveRecord::Base.transaction do
      refund = Refund.find(id)
      payment = Payment.find(refund.payment_id)
      order = payment.order
      validate_refund_links!(refund, payment, order)
      raise Error.new("REFUND_NOT_PENDING", "Hanya refund pending yang dapat diproses.") unless refund.status == "pending"
      raise Error.new("REFUND_PAYMENT_NOT_PAID", "Payment tidak lagi berstatus paid.") unless payment.status == "paid"

      now = Time.current
      refund.update!(
        status: "processed",
        processed_by: @admin,
        processed_at: now,
        reference_number: normalized_reference,
        notes: notes.to_s.strip.presence&.truncate(MAX_NOTES_LENGTH)
      )

      processed_total = payment.refunds.where(status: "processed").sum(:amount)
      if processed_total > payment.amount
        raise Error.new("REFUND_LIMIT_EXCEEDED", "Total refund processed melebihi jumlah payment yang diterima.")
      end

      payment.update!(status: "refunded") if processed_total == payment.amount
      audit!("refund_processed", refund, { payment_id: payment.id, order_id: order.id, amount: refund.amount, status: refund.status, reference_number: refund.reference_number })
      refund
    end
  end

  def reject!(id:, notes:)
    rejection_note = notes.to_s.strip
    raise Error.new("REFUND_REJECTION_NOTE_REQUIRED", "Catatan penolakan wajib diisi.") if rejection_note.blank?

    ActiveRecord::Base.transaction do
      refund = Refund.find(id)
      payment = Payment.find(refund.payment_id)
      order = payment.order
      validate_refund_links!(refund, payment, order)
      raise Error.new("REFUND_NOT_PENDING", "Hanya refund pending yang dapat ditolak.") unless refund.status == "pending"

      refund.update!(status: "rejected", notes: rejection_note.truncate(MAX_NOTES_LENGTH))
      audit!("refund_rejected", refund, { payment_id: payment.id, order_id: order.id, amount: refund.amount, status: refund.status })
      refund
    end
  end

  private

  def normalize_amount(amount)
    value = amount.to_s
    raise Error.new("REFUND_AMOUNT_INVALID", "Nominal refund harus berupa bilangan bulat positif.") unless value.match?(/\A[1-9]\d*\z/)

    value.to_i
  end

  def normalize_idempotency_key(key)
    value = key.to_s.strip
    raise Error.new("IDEMPOTENCY_KEY_REQUIRED", "Header Idempotency-Key wajib diisi.") if value.blank?
    raise Error.new("IDEMPOTENCY_KEY_INVALID", "Idempotency-Key maksimal 180 karakter.") if value.length > 180

    value
  end

  def request_fingerprint(payment_id, amount, reason)
    Digest::SHA256.hexdigest(JSON.generate(payment_id: payment_id.to_s, amount:, reason:))
  end

  def raise_payload_conflict!
    raise Conflict.new("REFUND_IDEMPOTENCY_CONFLICT", "Idempotency-Key sudah digunakan untuk payload refund yang berbeda.")
  end

  def refund_from_idempotency_record!(record, payment)
    refund = record.refund
    unless refund.payment_id == payment.id && record.payment_id == payment.id && record.admin_id == @admin.id
      raise Error.new("REFUND_IDEMPOTENCY_INVALID", "Referensi idempotency refund tidak konsisten.")
    end

    refund
  end

  def persist_idempotency_key!(admin:, payment:, refund:, key:, request_hash:)
    RefundIdempotencyKey.create!(admin:, payment:, refund:, key:, request_hash:)
  rescue ActiveRecord::RecordNotUnique => error
    raise IdempotencyClaimConflict.new(error)
  end

  def resolve_idempotency_claim!(payment_id:, key:, request_hash:, original_error:)
    record = RefundIdempotencyKey.find_by(admin_id: @admin.id, payment_id:, key:)
    raise original_error unless record
    raise_payload_conflict! unless record.request_hash == request_hash

    refund_from_idempotency_record!(record, Payment.find(payment_id))
  end

  def validate_refund_links!(refund, payment, order)
    return if refund.order_id == order.id && refund.payment.order_id == refund.order_id

    raise Error.new("REFUND_RELATION_INVALID", "Relasi payment dan order refund tidak konsisten.")
  end

  def audit!(action, refund, metadata)
    AuditLog.create!(
      user: @admin,
      action: action,
      resource_type: "Refund",
      resource_id: refund.id.to_s,
      ip_address: @request.remote_ip,
      user_agent: @request.user_agent,
      metadata: metadata.to_json
    )
  end
end
