class PaymentProofCleanupJob < ApplicationJob
  queue_as :default

  def perform(dry_run: true, cutoff: 1.year.ago)
    PaymentProofCleanupService.call(dry_run: dry_run, cutoff: cutoff)
  end
end
