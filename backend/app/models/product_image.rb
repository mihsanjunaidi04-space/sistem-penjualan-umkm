class ProductImage < ApplicationRecord
  belongs_to :product
  validates :product, :storage_key, presence: true
  validates :storage_key, length: { maximum: 255 }, format: { with: /\A[a-zA-Z0-9_\/. -]+\z/ }
  validates :alt_text, length: { maximum: 180 }, allow_blank: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
