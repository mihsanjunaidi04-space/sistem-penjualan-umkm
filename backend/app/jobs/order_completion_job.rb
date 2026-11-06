class OrderCompletionJob < ApplicationJob
  queue_as :default

  def perform(now = Time.current)
    OrderCompletionService.call(now: now)
  end
end
