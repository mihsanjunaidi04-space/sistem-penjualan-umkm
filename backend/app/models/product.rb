class Product < ApplicationRecord
  belongs_to :category
  has_many :product_images, dependent: :restrict_with_error
  has_many :cart_items, dependent: :restrict_with_error
  has_many :order_items, dependent: :restrict_with_error
  has_many :inventory_reservations, dependent: :restrict_with_error
  has_many :inventory_movements, dependent: :restrict_with_error
  has_many :reviews, dependent: :restrict_with_error
  has_many :wishlist_items, dependent: :restrict_with_error
  validates :name, presence: true, length: { maximum: 180 }
  validates :slug, presence: true, length: { maximum: 180 }, uniqueness: true,
            format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :sku, presence: true, length: { maximum: 120 }, uniqueness: true,
            format: { with: /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/ }
  validates :description, length: { maximum: 5_000 }, allow_blank: true
  validates :price, :stock_on_hand, :reserved_stock,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :reserved_stock_not_exceeding_stock_on_hand

  private

  def reserved_stock_not_exceeding_stock_on_hand
    return if reserved_stock.nil? || stock_on_hand.nil?
    errors.add(:reserved_stock, "must be less than or equal to stock_on_hand") if reserved_stock > stock_on_hand
  end
end
