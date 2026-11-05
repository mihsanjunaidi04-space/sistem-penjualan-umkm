class AddressesController < ApplicationController
  before_action :require_customer!

  def index
    addresses = current_user.addresses.order(is_default: :desc, id: :asc)
    render json: { success: true, data: { addresses: addresses.map { |address| serialize(address) } }, message: "Alamat berhasil diambil." }
  end

  private

  def serialize(address)
    { id: address.id, recipient_name: address.recipient_name, phone: address.phone, address_line: address.address_line, province: address.province, city: address.city, district: address.district, postal_code: address.postal_code, notes: address.notes, is_default: address.is_default }
  end
end
