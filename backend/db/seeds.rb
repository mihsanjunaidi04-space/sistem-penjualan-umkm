# frozen_string_literal: true

admin = User.find_or_initialize_by(email: 'admin@example.com')
admin.name = 'Admin UMKM'
admin.role = 'admin'
admin.is_active = true
admin.password = 'Password123!'
admin.save!

[{
  name: 'Elektronik',
  slug: 'elektronik',
  description: 'Perangkat elektronik',
  is_active: true
}, {
  name: 'Peralatan Rumah',
  slug: 'peralatan-rumah',
  description: 'Peralatan kebutuhan rumah',
  is_active: true
}].each do |attrs|
  Category.find_or_create_by!(slug: attrs[:slug]) do |category|
    category.name = attrs[:name]
    category.description = attrs[:description]
    category.is_active = attrs[:is_active]
  end
end

%w[Reguler Express].each do |name|
  cost = name == 'Reguler' ? 15_000 : 30_000
  estimated_days = name == 'Reguler' ? 3 : 1
  ShippingMethod.find_or_create_by!(name: name) do |method|
    method.description = "Pengiriman #{name.downcase}"
    method.estimated_days = estimated_days
    method.cost = cost
    method.is_active = true
  end
end

category = Category.first
if category
  Product.find_or_create_by!(sku: 'SKU-001') do |product|
    product.category = category
    product.name = 'Keyboard Mechanical'
    product.slug = 'keyboard-mechanical'
    product.description = 'Keyboard untuk kebutuhan kerja'
    product.price = 250_000
    product.stock_on_hand = 20
    product.reserved_stock = 0
    product.is_active = true
  end
end
