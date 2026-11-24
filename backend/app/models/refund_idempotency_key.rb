class RefundIdempotencyKey < ApplicationRecord
  belongs_to :admin, class_name: "User"
  belongs_to :payment
  belongs_to :refund

  validates :key, :request_hash, presence: true
  validates :key, length: { maximum: 180 }, uniqueness: { scope: [ :admin_id, :payment_id ] }
  validates :request_hash, format: { with: /\A[0-9a-f]{64}\z/ }
  validate :refund_belongs_to_payment

  private

  def refund_belongs_to_payment
    return if refund.blank? || payment.blank? || refund.payment_id == payment_id

    errors.add(:refund, "harus terkait dengan payment yang sama")
  end
end
