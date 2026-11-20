class DataRetentionCleanupJob < ApplicationJob
  queue_as :default

  def perform(before: 90.days.ago)
    DataRetentionCleanupService.anonymize_ip_user_agent!(before: before)
  end
end
