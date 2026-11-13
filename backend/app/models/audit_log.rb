class AuditLog < ApplicationRecord
  belongs_to :user, optional: true
  validates :action, :resource_type, presence: true

  def readonly?
    persisted? || super
  end

  def delete
    raise ActiveRecord::ReadOnlyRecord, "#{self.class} is marked as readonly" if readonly?

    super
  end
end
