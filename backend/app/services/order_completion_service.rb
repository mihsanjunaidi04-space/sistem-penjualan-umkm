class OrderCompletionService
  def self.call(now: Time.current)
    Order.where(status: "shipped").where("shipped_at <= ?", now - 7.days).find_each do |order|
      ActiveRecord::Base.transaction do
        order = Order.lock.find(order.id)
        next unless order.status == "shipped" && order.shipped_at && order.shipped_at <= now - 7.days
        order.update!(status: "completed", completed_at: now)
        AuditLog.create!(action: "order_completed", resource_type: "Order", resource_id: order.id.to_s, metadata: { shipped_at: order.shipped_at.iso8601 }.to_json)
      end
    end
  end
end
