class ShippingMethod < ApplicationRecord
  has_many :orders, dependent: :restrict_with_error
  has_many :shipments, dependent: :restrict_with_error
  validates :name, :estimated_days, presence: true
  validates :name, uniqueness: true
  validates :estimated_days, numericality: { only_integer: true, greater_than: 0 }
  validates :cost, numericality: { greater_than_or_equal_to: 0 }
end
