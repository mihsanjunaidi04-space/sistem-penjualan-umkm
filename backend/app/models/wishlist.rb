class Wishlist < ApplicationRecord
  belongs_to :user
  has_many :wishlist_items, dependent: :restrict_with_error
  validates :user, presence: true
end
