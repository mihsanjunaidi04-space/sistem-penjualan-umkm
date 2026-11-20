class DataRetentionCleanupService
  BATCH_SIZE = 100

  def self.anonymize_ip_user_agent!(before:)
    new(before: before).anonymize_ip_user_agent!
  end

  def initialize(before:)
    @before = before
  end

  def anonymize_ip_user_agent!
    candidate_ids = select_candidate_ids
    return 0 if candidate_ids.empty?

    update_candidates(candidate_ids)
  end

  private

  attr_reader :before

  def select_candidate_ids
    AuditLog
      .where("created_at <= ?", before)
      .where("ip_address IS NOT NULL OR user_agent IS NOT NULL")
      .order(:created_at, :id)
      .limit(BATCH_SIZE)
      .pluck(:id)
  end

  def update_candidates(candidate_ids)
    AuditLog
      .where(id: candidate_ids)
      .where("ip_address IS NOT NULL OR user_agent IS NOT NULL")
      .update_all(ip_address: nil, user_agent: nil)
  end
end
