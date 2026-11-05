class Payment < ApplicationRecord
  belongs_to :order
  belongs_to :verified_by, class_name: "User", foreign_key: :verified_by, optional: true
  has_many :payment_proofs, dependent: :restrict_with_error
  has_many :refunds, dependent: :restrict_with_error
  validates :order, :payment_method, :amount, presence: true
  validates :status, inclusion: { in: %w[pending waiting_verification paid rejected expired refunded] }
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
end
