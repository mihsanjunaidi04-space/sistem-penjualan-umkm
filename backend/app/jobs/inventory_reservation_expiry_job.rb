class InventoryReservationExpiryJob < ApplicationJob
  queue_as :default

  def perform
    InventoryReservationExpiryService.call
  end
end
