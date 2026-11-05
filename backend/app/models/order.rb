class Order < ApplicationRecord
  belongs_to :user
  belongs_to :shipping_method
  has_many :order_items, dependent: :restrict_with_error
  has_one :payment, dependent: :restrict_with_error
  has_one :shipment, dependent: :restrict_with_error
  has_many :inventory_reservations, dependent: :restrict_with_error
  has_many :cancellation_requests, dependent: :restrict_with_error
  has_many :refunds, dependent: :restrict_with_error
  validates :order_number, :user, :shipping_method, :payment_deadline_at, presence: true
  validates :status, inclusion: { in: %w[awaiting_payment processing shipped completed cancelled] }
  validates :subtotal, :discount_amount, :shipping_cost, :total_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :payment_deadline_at, comparison: { greater_than: :created_at }, on: :update, if: :created_at?
end
