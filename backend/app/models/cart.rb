class Cart < ApplicationRecord
  belongs_to :user
  has_many :cart_items, dependent: :restrict_with_error
  validates :user, presence: true
end
