class ProductImage < ApplicationRecord
  belongs_to :product
  validates :product, :storage_key, presence: true
  validates :position, numericality: { greater_than_or_equal_to: 0 }
end
