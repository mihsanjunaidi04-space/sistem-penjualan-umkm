class PaymentProofCleanupService
  BATCH_SIZE = 100
  STORAGE_KEY_FORMAT = /\A\h{64}\.(?:jpe?g|png|webp)\z/i

  def self.call(dry_run: true, cutoff: Time.current - 1.year, root: PrivatePaymentProofStorage::ROOT)
    new(cutoff: cutoff, root: root).call(dry_run: dry_run)
  end

  def initialize(cutoff:, root: PrivatePaymentProofStorage::ROOT)
    @cutoff = cutoff
    @root = root
  end

  def call(dry_run:)
    candidates = eligible_candidates
    stats = initial_stats

    candidates.each do |proof|
      stats[:processed] += 1
      result = evaluate_candidate(proof)

      if dry_run
        # In dry-run mode, just tally stats without touching filesystem
        case result
        when :would_delete then stats[:would_delete] += 1
        when :missing      then stats[:missing]     += 1
        when :failed       then stats[:failed]      += 1
        when :skipped      then stats[:skipped]     += 1
        end
      else
        # In execution mode, perform actual deletion
        action_result = execute_delete(proof)
        stats[action_result] += 1
      end
    end

    # Ensure invariants: only one mode's counter is non-zero
    stats[:deleted] = 0 if dry_run
    stats[:would_delete] = 0 unless dry_run

    log_batch_summary(stats, dry_run)
    stats
  end

  private

  attr_reader :cutoff, :root

  def eligible_candidates
    PaymentProof
      .joins(payment: :order)
      .where(
        "(payments.status = 'paid' AND orders.status = 'completed' AND orders.completed_at <= ?) OR " \
        "(payments.status = 'rejected' AND orders.status = 'cancelled' AND orders.cancelled_at <= ?) OR " \
        "(payments.status = 'expired' AND orders.status = 'cancelled' AND orders.cancelled_at <= ?)",
        cutoff, cutoff, cutoff
      )
      .order(:created_at, :id)
      .limit(BATCH_SIZE)
      .to_a
  end

  def initial_stats
    {
      processed: 0,
      deleted: 0,
      would_delete: 0,
      missing: 0,
      failed: 0,
      skipped: 0
    }
  end

  def evaluate_candidate(proof)
    # 1. Check duplicate reference first (fast check, no filesystem)
    return :skipped if duplicate_reference?(proof)
    # 2. Validate storage_key format
    return :failed  unless valid_storage_key?(proof.storage_key)
    # 3. Check file existence on disk
    check_file_access(proof.storage_key)
  end

  def duplicate_reference?(proof)
    PaymentProof.where(storage_key: proof.storage_key).where.not(id: proof.id).exists?
  end

  def valid_storage_key?(key)
    key.is_a?(String) && STORAGE_KEY_FORMAT.match?(key)
  end

  def check_file_access(storage_key)
    # Check if file exists on disk first
    candidate = root.join(storage_key)
    return :missing unless candidate.exist?
    # File exists and key format is valid = would_delete for dry-run
    :would_delete
  end

  def execute_delete(proof)
    # Re-check duplicate reference at execution time
    return :skipped if duplicate_reference?(proof)
    return :failed  unless valid_storage_key?(proof.storage_key)

    candidate_path = root.join(proof.storage_key).expand_path.to_s

    # Check if file exists first
    unless File.exist?(candidate_path)
      return :missing
    end

    # Direct file unlink
    begin
      File.unlink(candidate_path)
      :deleted
    rescue Errno::ENOENT
      :missing
    rescue SystemCallError => e
      classify_system_call_error(e)
    rescue => e
      Rails.logger.error "[PaymentProofCleanup] Unexpected error during deletion: #{e.class} #{e.message}"
      :failed
    end
  end

  def classify_system_call_error(error)
    case error
    when Errno::ENOENT
      :missing
    when Errno::EACCES, Errno::EPERM
      :failed
    else
      :failed
    end
  end

  def log_batch_summary(stats, dry_run)
    mode = dry_run ? "DRY_RUN" : "EXECUTE"
    Rails.logger.info(
      "[PaymentProofCleanup] #{mode} processed=#{stats[:processed]} " \
      "deleted=#{stats[:deleted]} would_delete=#{stats[:would_delete]} " \
      "missing=#{stats[:missing]} failed=#{stats[:failed]} skipped=#{stats[:skipped]} " \
      "cutoff=#{@cutoff.iso8601}"
    )
  end
end
