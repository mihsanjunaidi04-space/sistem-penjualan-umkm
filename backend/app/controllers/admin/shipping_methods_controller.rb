module Admin
  class ShippingMethodsController < ApplicationController
    before_action :require_admin!

    def index
      methods = ShippingMethod.order(:name)
      render json: { success: true, data: { shipping_methods: methods.map { |method| serialize(method) } }, message: "Daftar metode pengiriman berhasil diambil." }
    end

    def create
      shipping_method = ShippingMethod.new(shipping_method_params)
      saved = ActiveRecord::Base.transaction do
        next false unless shipping_method.save

        audit!("shipping_method_created", shipping_method, shipping_method.attributes.slice("name", "description", "estimated_days", "cost", "is_active"))
        true
      end

      return render_validation_error(shipping_method) unless saved

      render json: { success: true, data: { shipping_method: serialize(shipping_method) }, message: "Metode pengiriman berhasil dibuat." }, status: :created
    end

    def update
      outcome = ActiveRecord::Base.transaction do
        shipping_method = ShippingMethod.lock.find(params[:id])
        attributes = shipping_method_params
        if attributes[:name].present? && attributes[:name] != shipping_method.name && method_used?(shipping_method)
          next [ :name_immutable, shipping_method ]
        end

        next [ :invalid, shipping_method ] unless shipping_method.update(attributes)

        audit!("shipping_method_updated", shipping_method, shipping_method.saved_changes.slice("name", "description", "estimated_days", "cost", "is_active"))
        [ :saved, shipping_method ]
      end

      case outcome.first
      when :name_immutable
        render_error(:unprocessable_content, "SHIPPING_METHOD_NAME_IMMUTABLE", "Nama metode tidak dapat diubah setelah digunakan oleh order atau shipment.")
      when :invalid
        render_validation_error(outcome.last)
      else
        render json: { success: true, data: { shipping_method: serialize(outcome.last) }, message: "Metode pengiriman berhasil diubah." }
      end
    rescue ActiveRecord::RecordNotFound
      render_error(:not_found, "SHIPPING_METHOD_NOT_FOUND", "Metode pengiriman tidak ditemukan.")
    end

    private

    def shipping_method_params
      params.permit(:name, :description, :estimated_days, :cost, :is_active)
    end

    def method_used?(shipping_method)
      shipping_method.orders.exists? || shipping_method.shipments.exists?
    end

    def render_validation_error(shipping_method)
      render_error(:unprocessable_content, "VALIDATION_ERROR", "Data metode pengiriman tidak valid.", shipping_method.errors.to_hash)
    end

    def audit!(action, shipping_method, metadata)
      AuditLog.create!(
        user: current_user,
        action: action,
        resource_type: "ShippingMethod",
        resource_id: shipping_method.id.to_s,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: metadata.to_json
      )
    end

    def serialize(shipping_method)
      {
        id: shipping_method.id,
        name: shipping_method.name,
        description: shipping_method.description,
        estimated_days: shipping_method.estimated_days,
        cost: shipping_method.cost,
        is_active: shipping_method.is_active
      }
    end
  end
end
