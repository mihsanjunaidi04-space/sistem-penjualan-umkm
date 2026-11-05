class Category < ApplicationRecord
  has_many :products, dependent: :restrict_with_error
  validates :name, presence: true, length: { maximum: 150 }
  validates :slug, presence: true, length: { maximum: 120 }, uniqueness: true,
            format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :description, length: { maximum: 2_000 }, allow_blank: true
end
