class Address < ApplicationRecord
  belongs_to :user
  validates :recipient_name, presence: true, length: { maximum: 150 }
  validates :phone, presence: true, length: { maximum: 30 }
  validates :address_line, presence: true
  validates :province, :city, :district, :postal_code, presence: true
end
