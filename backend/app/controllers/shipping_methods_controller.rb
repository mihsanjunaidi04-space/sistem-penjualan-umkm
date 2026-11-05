class ShippingMethodsController < ApplicationController
  before_action :require_customer!

  def index
    methods = ShippingMethod.where(is_active: true).order(:cost, :name)
    render json: { success: true, data: { shipping_methods: methods.map { |method| serialize(method) } }, message: "Metode pengiriman berhasil diambil." }
  end

  private

  def serialize(method)
    { id: method.id, name: method.name, description: method.description, estimated_days: method.estimated_days, cost: method.cost }
  end
end
