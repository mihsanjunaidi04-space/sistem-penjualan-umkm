class StoreSetting < ApplicationRecord
  belongs_to :updated_by, class_name: "User", foreign_key: :updated_by, optional: true
  validates :setting_key, :setting_value, presence: true
  validates :setting_key, uniqueness: true
end
