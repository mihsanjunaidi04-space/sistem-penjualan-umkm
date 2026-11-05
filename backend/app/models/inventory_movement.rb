class InventoryMovement < ApplicationRecord
  belongs_to :product
  belongs_to :order, optional: true
  belongs_to :created_by, class_name: "User", foreign_key: :created_by, optional: true
  validates :product, :movement_type, :quantity, :stock_before, :stock_after, presence: true
  validates :movement_type, inclusion: { in: %w[stock_in stock_out reservation reservation_release reservation_conversion adjustment return] }
end
