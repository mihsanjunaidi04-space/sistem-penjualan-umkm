class PaymentProof < ApplicationRecord
  belongs_to :payment
  has_many :verification_events, dependent: :restrict_with_error
  validates :payment, :storage_key, :original_filename, :uploaded_at, presence: true
  validates :status, inclusion: { in: %w[submitted approved rejected] }
  validates :file_size, numericality: { greater_than_or_equal_to: 0 }
end
