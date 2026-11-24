class Refund < ApplicationRecord
  STATUSES = %w[pending processed rejected].freeze

  belongs_to :payment
  belongs_to :order
  belongs_to :processed_by, class_name: "User", foreign_key: :processed_by, optional: true

  validates :payment, :order, :amount, :reason, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :amount, numericality: { only_integer: true, greater_than: 0 }
  validates :reference_number, presence: true, if: :processed?
  validates :processed_by, :processed_at, presence: true, if: :processed?
  validates :notes, presence: true, if: :rejected?
  validate :payment_and_order_match
  validate :processor_must_be_admin, if: :processed?

  private

  def processed?
    status == "processed"
  end

  def rejected?
    status == "rejected"
  end

  def payment_and_order_match
    return if payment.blank? || order.blank? || payment.order_id == order_id

    errors.add(:order, "harus merupakan order dari payment refund")
  end

  def processor_must_be_admin
    return if processed_by&.admin?

    errors.add(:processed_by, "harus merupakan admin")
  end
end
