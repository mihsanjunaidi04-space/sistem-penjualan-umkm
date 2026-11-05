class IdempotencyKey < ApplicationRecord
  belongs_to :user
  validates :user, :key, :request_hash, :response_status, :expires_at, presence: true
  validates :key, uniqueness: { scope: :user_id }
  validates :response_status, numericality: { greater_than_or_equal_to: 100 }
end
