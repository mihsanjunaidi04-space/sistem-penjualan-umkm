class VoucherRedemption < ApplicationRecord
  belongs_to :voucher
  belongs_to :user
  belongs_to :order, optional: true
  validates :voucher, :user, presence: true
  validates :status, inclusion: { in: %w[reserved used released] }
end
