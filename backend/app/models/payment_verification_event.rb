class PaymentVerificationEvent < ApplicationRecord
  belongs_to :payment
  belongs_to :payment_proof, optional: true
  belongs_to :admin, class_name: "User", foreign_key: :admin_id

  validates :decision, inclusion: { in: %w[approved rejected] }
end
