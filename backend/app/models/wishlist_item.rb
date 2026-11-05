class WishlistItem < ApplicationRecord
  belongs_to :wishlist
  belongs_to :product
  validates :wishlist, :product, presence: true
end
