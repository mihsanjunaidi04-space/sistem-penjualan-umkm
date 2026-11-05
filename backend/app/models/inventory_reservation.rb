class InventoryReservation < ApplicationRecord
  belongs_to :order
  belongs_to :product
  validates :order, :product, :quantity, presence: true
  validates :status, inclusion: { in: %w[reserved converted released] }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
end
