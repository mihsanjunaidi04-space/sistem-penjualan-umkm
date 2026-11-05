class Notification < ApplicationRecord
  self.inheritance_column = :_type_disabled
  belongs_to :user
  self.inheritance_column = :_type_disabled
  validates :user, :type, :title, :message, presence: true
end
