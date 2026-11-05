class CancellationRequest < ApplicationRecord
  belongs_to :order
  belongs_to :requested_by, class_name: "User", foreign_key: :requested_by
  belongs_to :reviewed_by, class_name: "User", foreign_key: :reviewed_by, optional: true
  validates :order, :requested_by, :reason, :status, presence: true
  validates :status, inclusion: { in: %w[pending approved rejected] }
end
