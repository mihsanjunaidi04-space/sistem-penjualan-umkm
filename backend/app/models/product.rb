class Product < ApplicationRecord
  belongs_to :category
  has_many :product_images, dependent: :restrict_with_error
  has_many :cart_items, dependent: :restrict_with_error
  has_many :order_items, dependent: :restrict_with_error
  has_many :inventory_reservations, dependent: :restrict_with_error
  has_many :inventory_movements, dependent: :restrict_with_error
  has_many :reviews, dependent: :restrict_with_error
  has_many :wishlist_items, dependent: :restrict_with_error
  validates :name, :slug, :sku, presence: true
  validates :slug, :sku, uniqueness: true
  validates :price, :stock_on_hand, :reserved_stock, numericality: { greater_than_or_equal_to: 0 }
  validate :reserved_stock_not_exceeding_stock_on_hand

  private

  def reserved_stock_not_exceeding_stock_on_hand
    return if reserved_stock.nil? || stock_on_hand.nil?
    errors.add(:reserved_stock, "must be less than or equal to stock_on_hand") if reserved_stock > stock_on_hand
  end
end
