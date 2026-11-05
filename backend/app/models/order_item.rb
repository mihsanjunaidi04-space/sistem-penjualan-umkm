class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product
  has_one :review, dependent: :restrict_with_error
  validates :order, :product, :product_name_snapshot, :sku_snapshot, presence: true
  validates :unit_price, :subtotal, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
end
