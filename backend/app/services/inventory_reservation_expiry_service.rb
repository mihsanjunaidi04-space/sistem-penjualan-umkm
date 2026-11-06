class InventoryReservationExpiryService
  def self.call(now: Time.current)
    InventoryReservation.where(status: "reserved").where("expires_at <= ?", now).find_each do |reservation|
      release(reservation, now)
    end
  end

  def self.release(reservation, now)
    ActiveRecord::Base.transaction do
      reservation = InventoryReservation.lock.find(reservation.id)
      next unless reservation.status == "reserved" && reservation.expires_at && reservation.expires_at <= now
      order = reservation.order
      payment = order.payment
      next if payment&.payment_proofs&.where("uploaded_at <= ?", reservation.expires_at)&.exists?

      product = Product.find(reservation.product_id)
      available_before = product.stock_on_hand - product.reserved_stock
      updated = Product.where(id: product.id).where("reserved_stock >= ?", reservation.quantity).update_all([ "reserved_stock = reserved_stock - ?", reservation.quantity ])
      raise ActiveRecord::Rollback unless updated == 1

      product.reload
      reservation.update!(status: "released", released_at: now)
      InventoryMovement.create!(product: product, order: order, movement_type: "reservation_release", quantity: reservation.quantity, stock_before: available_before, stock_after: product.stock_on_hand - product.reserved_stock, reference: order.order_number, notes: "Reservasi kedaluwarsa")
      payment&.update!(status: "expired")
      order.update!(status: "cancelled", cancelled_at: now)
    end
  end
end
