class Refund < ApplicationRecord
  belongs_to :payment
  belongs_to :order
  belongs_to :processed_by, class_name: "User", foreign_key: :processed_by, optional: true
  validates :payment, :order, :amount, :reason, :status, presence: true
  validates :status, inclusion: { in: %w[pending processed rejected] }
  validates :amount, numericality: { greater_than: 0 }
end
