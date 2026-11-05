class AuditLog < ApplicationRecord
  belongs_to :user, optional: true
  validates :action, :resource_type, presence: true
end
