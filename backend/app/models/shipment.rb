class Shipment < ApplicationRecord
  belongs_to :order
  belongs_to :shipping_method
  validates :order, :shipping_method, presence: true
  validates :status, inclusion: { in: %w[not_shipped packed shipped delivered] }
end
