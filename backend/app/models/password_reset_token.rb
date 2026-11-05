class PasswordResetToken < ApplicationRecord
  belongs_to :user
  validates :user, presence: true
  validates :token_digest, presence: true
  validates :expires_at, presence: true
end
