class Review < ApplicationRecord
  belongs_to :user
  belongs_to :product
  belongs_to :order_item
  validates :user, :product, :order_item, :rating, presence: true
  validates :rating, inclusion: { in: 1..5 }
end
