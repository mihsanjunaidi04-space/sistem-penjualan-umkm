class PaymentProofCleanupJob < ApplicationJob
  queue_as :default

  def perform(dry_run: true, cutoff: 1.year.ago, root: nil)
    options = { dry_run: dry_run, cutoff: cutoff }
    options[:root] = root if root
    PaymentProofCleanupService.call(**options)
  end
end
