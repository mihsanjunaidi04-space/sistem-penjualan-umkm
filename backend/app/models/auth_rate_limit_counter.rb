class AuthRateLimitCounter < ApplicationRecord
  validates :key, :count, :window_started_at, :expires_at, presence: true
  validates :count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
