class Voucher < ApplicationRecord
  has_many :voucher_redemptions, dependent: :restrict_with_error
  validates :code, :discount_type, presence: true
  validates :code, uniqueness: true
  validates :discount_type, inclusion: { in: %w[fixed percentage] }
  validates :discount_value, :minimum_purchase, :maximum_discount, :usage_limit, :per_user_limit, numericality: { greater_than_or_equal_to: 0 }
end
