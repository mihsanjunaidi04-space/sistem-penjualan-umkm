class ShipmentService
  class Error < StandardError
    attr_reader :code
    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  def self.create!(order_id:, admin:, request:)
    ActiveRecord::Base.transaction do
      order = Order.lock.includes(:payment, :shipment, :shipping_method).find(order_id)
      raise Error.new("SHIPMENT_NOT_ALLOWED", "Shipment hanya dapat dibuat untuk order processing.") unless order.status == "processing" && order.payment&.status == "paid" && order.shipment.blank?
      shipment = order.create_shipment!(shipping_method: order.shipping_method, recipient_name_snapshot: order.recipient_name_snapshot.to_s, shipping_address_snapshot: order.shipping_address_snapshot.to_s, status: "not_shipped")
      audit!(admin, "shipment_created", shipment, order, request)
      shipment
    end
  end

  def self.pack!(id:, admin:, request:)
    transition!(id, "not_shipped", "packed", admin, request)
  end

  def self.ship!(id:, tracking_number:, admin:, request:)
    raise Error.new("TRACKING_NUMBER_REQUIRED", "Tracking number wajib diisi.") if tracking_number.to_s.strip.blank?
    ActiveRecord::Base.transaction do
      shipment = Shipment.lock.find(id)
      order = Order.lock.find(shipment.order_id)
      raise Error.new("INVALID_SHIPMENT_STATE", "Shipment tidak dapat dikirim.") unless shipment.status == "packed" && order.status == "processing" && order.payment&.status == "paid"
      now = Time.current
      shipment.update!(status: "shipped", tracking_number: tracking_number.to_s.strip.truncate(120), shipped_at: now)
      order.update!(status: "shipped", shipped_at: now)
      audit!(admin, "shipment_shipped", shipment, order, request)
      shipment
    end
  end

  def self.deliver!(id:, admin:, request:)
    transition!(id, "shipped", "delivered", admin, request, delivered_at: Time.current)
  end

  def self.transition!(id, from, to, admin, request, attributes = {})
    ActiveRecord::Base.transaction do
      shipment = Shipment.lock.find(id)
      order = Order.lock.find(shipment.order_id)
      raise Error.new("INVALID_SHIPMENT_STATE", "Transisi shipment tidak valid.") unless shipment.status == from
      shipment.update!(attributes.merge(status: to))
      audit!(admin, "shipment_#{to}", shipment, order, request)
      shipment
    end
  end

  def self.audit!(admin, action, shipment, order, request)
    AuditLog.create!(user: admin, action: action, resource_type: "Shipment", resource_id: shipment.id.to_s, ip_address: request.remote_ip, user_agent: request.user_agent, metadata: { order_id: order.id, status: shipment.status }.to_json)
  end
end
