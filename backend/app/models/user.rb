class User < ApplicationRecord
  has_many :addresses, dependent: :restrict_with_error
  has_many :orders, dependent: :restrict_with_error
  has_many :carts, dependent: :restrict_with_error
  has_many :notifications, dependent: :restrict_with_error
  has_many :audit_logs, dependent: :restrict_with_error
  has_many :wishlists, dependent: :restrict_with_error
  has_many :reviews, dependent: :restrict_with_error
  has_many :password_reset_tokens, dependent: :restrict_with_error
  has_many :idempotency_keys, dependent: :restrict_with_error

  has_secure_password

  validates :name, presence: true, length: { maximum: 150 }
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, inclusion: { in: %w[admin customer] }
  validates :password, length: { minimum: 8 }, if: -> { password.present? }

  def admin?
    role.to_s == "admin"
  end

  def customer?
    role.to_s == "customer"
  end
end
