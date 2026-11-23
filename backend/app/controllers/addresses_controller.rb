class AddressesController < ApplicationController
  MAX_UNIQUE_CONSTRAINT_ATTEMPTS = 3

  before_action :require_customer!
  before_action :set_address, only: %i[update destroy]

  def index
    addresses = current_user.addresses.order(is_default: :desc, id: :asc)
    render json: { success: true, data: { addresses: addresses.map { |address| serialize(address) } }, message: "Alamat berhasil diambil." }
  end

  def create
    address = with_unique_constraint_retry do
      ActiveRecord::Base.transaction do
        address = current_user.addresses.build(address_params)

        # Handle is_default logic
        if params[:is_default] == true
          address.is_default = true
        elsif params[:is_default] == false
          address.is_default = false
        elsif params[:is_default].nil? && current_user.addresses.count == 0
          address.is_default = true
        end

        # If this address is set as default, unset other defaults within the same transaction
        if address.is_default?
          current_user.addresses.where(is_default: true).update_all(is_default: false)
        end

        address.save!
        address
      end
    end

    render json: { success: true, data: { address: serialize(address) }, message: "Alamat berhasil ditambahkan." }, status: :created
  rescue ActiveRecord::RecordNotUnique
    render_error(:conflict, "ADDRESS_DEFAULT_CONFLICT", "Alamat default berubah bersamaan. Silakan coba lagi.")
  rescue ActiveRecord::RecordInvalid => e
    render_error(:unprocessable_entity, "VALIDATION_ERROR", e.record.errors.full_messages.join(", "))
  end

  def update
    unless address
      render_error(:not_found, "NOT_FOUND", "Alamat tidak ditemukan.")
      return
    end

    with_unique_constraint_retry do
      ActiveRecord::Base.transaction do
        address.assign_attributes(address_params)

        # Unset the current default before setting this address to avoid violating
        # the partial unique index; both changes roll back together on failure.
        if address.is_default?
          current_user.addresses.where.not(id: address.id).where(is_default: true).update_all(is_default: false)
        end

        address.save!
      end
    end

    render json: { success: true, data: { address: serialize(address) }, message: "Alamat berhasil diperbarui." }
  rescue ActiveRecord::RecordNotUnique
    render_error(:conflict, "ADDRESS_DEFAULT_CONFLICT", "Alamat default berubah bersamaan. Silakan coba lagi.")
  rescue ActiveRecord::RecordInvalid => e
    render_error(:unprocessable_entity, "VALIDATION_ERROR", e.record.errors.full_messages.join(", "))
  end

  def destroy
    unless address
      render_error(:not_found, "NOT_FOUND", "Alamat tidak ditemukan.")
      return
    end

    was_default = address.is_default?

    destroyed = ActiveRecord::Base.transaction do
      if address.destroy
        # Jika alamat yang dihapus adalah default, tetapkan alamat lain sebagai default jika ada
        if was_default
          remaining_address = current_user.addresses.first
          if remaining_address
            remaining_address.update!(is_default: true)
          end
        end

        true
      else
        false
      end
    end

    if destroyed
      render json: { success: true, message: "Alamat berhasil dihapus." }
    else
      render_error(:unprocessable_entity, "VALIDATION_ERROR", address.errors.full_messages.join(", "))
    end
  end

  private

  def set_address
    @address = current_user.addresses.find_by(id: params[:id])
  end

  def address
    @address
  end

  def serialize(address)
    {
      id: address.id,
      recipient_name: address.recipient_name,
      phone: address.phone,
      address_line: address.address_line,
      province: address.province,
      city: address.city,
      district: address.district,
      postal_code: address.postal_code,
      notes: address.notes,
      is_default: address.is_default
    }
  end

  def address_params
    params.permit(:recipient_name, :phone, :address_line, :province, :city, :district, :postal_code, :notes, :is_default)
  end

  def with_unique_constraint_retry
    attempts = 0

    begin
      attempts += 1
      yield
    rescue ActiveRecord::RecordNotUnique
      retry if attempts < MAX_UNIQUE_CONSTRAINT_ATTEMPTS

      raise
    end
  end
end
