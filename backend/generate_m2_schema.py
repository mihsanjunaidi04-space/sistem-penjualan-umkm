import re
from pathlib import Path
from textwrap import dedent

root = Path(r'D:\sistem-penjualan-umkm')

# table metadata: name -> list of columns, indexes, check constraints, unique columns.
TABLES = [
    {
        'name': 'users',
        'columns': [
            ('name', 'string', {'null': False, 'limit': 150}),
            ('email', 'string', {'null': False, 'limit': 255}),
            ('password_digest', 'string', {'null': False}),
            ('role', 'string', {'null': False, 'default': 'customer', 'limit': 20}),
            ('phone', 'string', {'limit': 30}),
            ('is_active', 'boolean', {'null': False, 'default': True}),
            ('email_verified_at', 'datetime'),
        ],
        'indexes': [('email', {'unique': True})],
        'checks': [("role IN ('admin', 'customer')", 'users_role_check')],
    },
    {
        'name': 'addresses',
        'columns': [
            ('user_id', 'bigint', {'null': False}),
            ('recipient_name', 'string', {'null': False, 'limit': 150}),
            ('phone', 'string', {'null': False, 'limit': 30}),
            ('address_line', 'text', {'null': False}),
            ('province', 'string', {'null': False, 'limit': 120}),
            ('city', 'string', {'null': False, 'limit': 120}),
            ('district', 'string', {'null': False, 'limit': 120}),
            ('postal_code', 'string', {'null': False, 'limit': 20}),
            ('notes', 'text'),
            ('is_default', 'boolean', {'null': False, 'default': False}),
        ],
        'indexes': [('user_id', {})],
        'foreign_keys': [('user_id', 'users')],
    },
    {
        'name': 'password_reset_tokens',
        'columns': [
            ('user_id', 'bigint', {'null': False}),
            ('token_digest', 'string', {'null': False}),
            ('expires_at', 'datetime', {'null': False}),
            ('used_at', 'datetime'),
        ],
        'indexes': [('user_id', {})],
        'foreign_keys': [('user_id', 'users')],
    },
    {
        'name': 'categories',
        'columns': [
            ('name', 'string', {'null': False, 'limit': 150}),
            ('slug', 'string', {'null': False, 'limit': 120}),
            ('description', 'text'),
            ('is_active', 'boolean', {'null': False, 'default': True}),
        ],
        'indexes': [('slug', {'unique': True})],
    },
    {
        'name': 'products',
        'columns': [
            ('category_id', 'bigint', {'null': False}),
            ('name', 'string', {'null': False, 'limit': 180}),
            ('slug', 'string', {'null': False, 'limit': 180}),
            ('sku', 'string', {'null': False, 'limit': 120}),
            ('description', 'text'),
            ('price', 'integer', {'null': False, 'default': 0}),
            ('stock_on_hand', 'integer', {'null': False, 'default': 0}),
            ('reserved_stock', 'integer', {'null': False, 'default': 0}),
            ('is_active', 'boolean', {'null': False, 'default': True}),
        ],
        'indexes': [('category_id', {}), ('slug', {'unique': True}), ('sku', {'unique': True})],
        'foreign_keys': [('category_id', 'categories')],
        'checks': [
            ('price >= 0', 'products_price_non_negative'),
            ('stock_on_hand >= 0', 'products_stock_on_hand_non_negative'),
            ('reserved_stock >= 0', 'products_reserved_stock_non_negative'),
            ('reserved_stock <= stock_on_hand', 'products_reserved_stock_within_stock'),
        ],
    },
    {
        'name': 'product_images',
        'columns': [
            ('product_id', 'bigint', {'null': False}),
            ('storage_key', 'string', {'null': False}),
            ('alt_text', 'string', {'limit': 180}),
            ('position', 'integer', {'null': False, 'default': 0}),
        ],
        'indexes': [('product_id', {})],
        'foreign_keys': [('product_id', 'products')],
        'checks': [('position >= 0', 'product_images_position_non_negative')],
    },
    {
        'name': 'carts',
        'columns': [('user_id', 'bigint', {'null': False})],
        'indexes': [('user_id', {'unique': True})],
        'foreign_keys': [('user_id', 'users')],
    },
    {
        'name': 'cart_items',
        'columns': [
            ('cart_id', 'bigint', {'null': False}),
            ('product_id', 'bigint', {'null': False}),
            ('quantity', 'integer', {'null': False}),
        ],
        'indexes': [('cart_id', {}), ('product_id', {}), (('cart_id', 'product_id'), {'unique': True})],
        'foreign_keys': [('cart_id', 'carts'), ('product_id', 'products')],
        'checks': [('quantity > 0', 'cart_items_quantity_positive')],
    },
    {
        'name': 'orders',
        'columns': [
            ('order_number', 'string', {'null': False, 'limit': 80}),
            ('user_id', 'bigint', {'null': False}),
            ('shipping_method_id', 'bigint', {'null': False}),
            ('status', 'string', {'null': False, 'default': 'awaiting_payment', 'limit': 30}),
            ('subtotal', 'integer', {'null': False, 'default': 0}),
            ('discount_amount', 'integer', {'null': False, 'default': 0}),
            ('shipping_cost', 'integer', {'null': False, 'default': 0}),
            ('total_amount', 'integer', {'null': False, 'default': 0}),
            ('voucher_code_snapshot', 'string', {'limit': 80}),
            ('recipient_name_snapshot', 'string', {'limit': 150}),
            ('recipient_phone_snapshot', 'string', {'limit': 30}),
            ('shipping_address_snapshot', 'text'),
            ('customer_notes', 'text'),
            ('payment_deadline_at', 'datetime', {'null': False}),
            ('shipped_at', 'datetime'),
            ('completed_at', 'datetime'),
            ('cancelled_at', 'datetime'),
        ],
        'indexes': [('order_number', {'unique': True}), ('user_id', {}), ('shipping_method_id', {}), ('status', {}), ('created_at', {})],
        'foreign_keys': [('user_id', 'users'), ('shipping_method_id', 'shipping_methods')],
        'checks': [
            ('subtotal >= 0', 'orders_subtotal_non_negative'),
            ('discount_amount >= 0', 'orders_discount_amount_non_negative'),
            ('shipping_cost >= 0', 'orders_shipping_cost_non_negative'),
            ('total_amount >= 0', 'orders_total_amount_non_negative'),
            ("status IN ('awaiting_payment', 'processing', 'shipped', 'completed', 'cancelled')", 'orders_status_check'),
        ],
    },
    {
        'name': 'order_items',
        'columns': [
            ('order_id', 'bigint', {'null': False}),
            ('product_id', 'bigint', {'null': False}),
            ('product_name_snapshot', 'string', {'null': False, 'limit': 180}),
            ('sku_snapshot', 'string', {'null': False, 'limit': 120}),
            ('unit_price', 'integer', {'null': False}),
            ('quantity', 'integer', {'null': False}),
            ('subtotal', 'integer', {'null': False}),
        ],
        'indexes': [('order_id', {}), ('product_id', {})],
        'foreign_keys': [('order_id', 'orders'), ('product_id', 'products')],
        'checks': [
            ('unit_price >= 0', 'order_items_unit_price_non_negative'),
            ('quantity > 0', 'order_items_quantity_positive'),
            ('subtotal >= 0', 'order_items_subtotal_non_negative'),
        ],
    },
    {
        'name': 'payments',
        'columns': [
            ('order_id', 'bigint', {'null': False}),
            ('payment_method', 'string', {'null': False, 'limit': 40}),
            ('amount', 'integer', {'null': False}),
            ('status', 'string', {'null': False, 'default': 'pending', 'limit': 30}),
            ('verified_by', 'bigint'),
            ('verified_at', 'datetime'),
            ('rejection_reason', 'text'),
        ],
        'indexes': [('order_id', {'unique': True}), ('status', {}), ('verified_by', {})],
        'foreign_keys': [('order_id', 'orders'), ('verified_by', 'users')],
        'checks': [
            ('amount >= 0', 'payments_amount_non_negative'),
            ("status IN ('pending', 'waiting_verification', 'paid', 'rejected', 'expired', 'refunded')", 'payments_status_check'),
        ],
    },
    {
        'name': 'payment_proofs',
        'columns': [
            ('payment_id', 'bigint', {'null': False}),
            ('storage_key', 'string', {'null': False}),
            ('original_filename', 'string', {'null': False, 'limit': 255}),
            ('mime_type', 'string', {'limit': 120}),
            ('file_size', 'integer', {'null': False, 'default': 0}),
            ('status', 'string', {'null': False, 'default': 'submitted', 'limit': 30}),
            ('uploaded_at', 'datetime', {'null': False}),
            ('reviewed_at', 'datetime'),
        ],
        'indexes': [('payment_id', {}), ('status', {})],
        'foreign_keys': [('payment_id', 'payments')],
        'checks': [
            ('file_size >= 0', 'payment_proofs_file_size_non_negative'),
            ("status IN ('submitted', 'approved', 'rejected')", 'payment_proofs_status_check'),
        ],
    },
    {
        'name': 'inventory_reservations',
        'columns': [
            ('order_id', 'bigint', {'null': False}),
            ('product_id', 'bigint', {'null': False}),
            ('quantity', 'integer', {'null': False}),
            ('status', 'string', {'null': False, 'default': 'reserved', 'limit': 30}),
            ('expires_at', 'datetime'),
            ('converted_at', 'datetime'),
            ('released_at', 'datetime'),
        ],
        'indexes': [('order_id', {}), ('product_id', {}), ('status', {}), ('expires_at', {}), (('order_id', 'product_id'), {'unique': True})],
        'foreign_keys': [('order_id', 'orders'), ('product_id', 'products')],
        'checks': [
            ('quantity > 0', 'inventory_reservations_quantity_positive'),
            ("status IN ('reserved', 'converted', 'released')", 'inventory_reservations_status_check'),
        ],
    },
    {
        'name': 'inventory_movements',
        'columns': [
            ('product_id', 'bigint', {'null': False}),
            ('order_id', 'bigint'),
            ('movement_type', 'string', {'null': False, 'limit': 40}),
            ('quantity', 'integer', {'null': False}),
            ('stock_before', 'integer', {'null': False}),
            ('stock_after', 'integer', {'null': False}),
            ('reference', 'string', {'limit': 120}),
            ('notes', 'text'),
            ('created_by', 'bigint'),
        ],
        'indexes': [('product_id', {}), ('order_id', {}), ('created_by', {})],
        'foreign_keys': [('product_id', 'products'), ('order_id', 'orders'), ('created_by', 'users')],
        'checks': [
            ("movement_type IN ('stock_in', 'stock_out', 'reservation', 'reservation_release', 'reservation_conversion', 'adjustment', 'return')", 'inventory_movements_type_check'),
            ('quantity != 0', 'inventory_movements_quantity_non_zero'),
        ],
    },
    {
        'name': 'shipping_methods',
        'columns': [
            ('name', 'string', {'null': False, 'limit': 120}),
            ('description', 'text'),
            ('estimated_days', 'integer', {'null': False}),
            ('cost', 'integer', {'null': False, 'default': 0}),
            ('is_active', 'boolean', {'null': False, 'default': True}),
        ],
        'indexes': [('name', {'unique': True})],
        'checks': [
            ('estimated_days > 0', 'shipping_methods_estimated_days_positive'),
            ('cost >= 0', 'shipping_methods_cost_non_negative'),
        ],
    },
    {
        'name': 'shipments',
        'columns': [
            ('order_id', 'bigint', {'null': False}),
            ('shipping_method_id', 'bigint', {'null': False}),
            ('recipient_name_snapshot', 'string', {'null': False, 'limit': 150}),
            ('shipping_address_snapshot', 'text', {'null': False}),
            ('tracking_number', 'string', {'limit': 120}),
            ('status', 'string', {'null': False, 'default': 'not_shipped', 'limit': 30}),
            ('shipped_at', 'datetime'),
            ('delivered_at', 'datetime'),
        ],
        'indexes': [('order_id', {'unique': True}), ('shipping_method_id', {}), ('status', {})],
        'foreign_keys': [('order_id', 'orders'), ('shipping_method_id', 'shipping_methods')],
        'checks': [("status IN ('not_shipped', 'packed', 'shipped', 'delivered')", 'shipments_status_check')],
    },
    {
        'name': 'vouchers',
        'columns': [
            ('code', 'string', {'null': False, 'limit': 80}),
            ('description', 'text'),
            ('discount_type', 'string', {'null': False, 'limit': 20}),
            ('discount_value', 'integer', {'null': False, 'default': 0}),
            ('minimum_purchase', 'integer', {'null': False, 'default': 0}),
            ('maximum_discount', 'integer', {'null': False, 'default': 0}),
            ('usage_limit', 'integer', {'null': False, 'default': 0}),
            ('per_user_limit', 'integer', {'null': False, 'default': 0}),
            ('starts_at', 'datetime'),
            ('expires_at', 'datetime'),
            ('is_active', 'boolean', {'null': False, 'default': True}),
        ],
        'indexes': [('code', {'unique': True}), ('is_active', {})],
        'checks': [
            ("discount_type IN ('fixed', 'percentage')", 'vouchers_discount_type_check'),
            ('discount_value >= 0', 'vouchers_discount_value_non_negative'),
            ('minimum_purchase >= 0', 'vouchers_minimum_purchase_non_negative'),
            ('maximum_discount >= 0', 'vouchers_maximum_discount_non_negative'),
            ('usage_limit >= 0', 'vouchers_usage_limit_non_negative'),
            ('per_user_limit >= 0', 'vouchers_per_user_limit_non_negative'),
        ],
    },
    {
        'name': 'voucher_redemptions',
        'columns': [
            ('voucher_id', 'bigint', {'null': False}),
            ('user_id', 'bigint', {'null': False}),
            ('order_id', 'bigint'),
            ('status', 'string', {'null': False, 'default': 'reserved', 'limit': 20}),
            ('reserved_at', 'datetime'),
            ('used_at', 'datetime'),
            ('released_at', 'datetime'),
        ],
        'indexes': [('voucher_id', {}), ('user_id', {}), ('order_id', {'unique': True}), ('status', {})],
        'foreign_keys': [('voucher_id', 'vouchers'), ('user_id', 'users'), ('order_id', 'orders')],
        'checks': [("status IN ('reserved', 'used', 'released')", 'voucher_redemptions_status_check')],
    },
    {
        'name': 'wishlists',
        'columns': [('user_id', 'bigint', {'null': False})],
        'indexes': [('user_id', {'unique': True})],
        'foreign_keys': [('user_id', 'users')],
    },
    {
        'name': 'wishlist_items',
        'columns': [
            ('wishlist_id', 'bigint', {'null': False}),
            ('product_id', 'bigint', {'null': False}),
        ],
        'indexes': [('wishlist_id', {}), ('product_id', {}), (('wishlist_id', 'product_id'), {'unique': True})],
        'foreign_keys': [('wishlist_id', 'wishlists'), ('product_id', 'products')],
    },
    {
        'name': 'reviews',
        'columns': [
            ('user_id', 'bigint', {'null': False}),
            ('product_id', 'bigint', {'null': False}),
            ('order_item_id', 'bigint', {'null': False}),
            ('rating', 'integer', {'null': False}),
            ('comment', 'text'),
            ('is_visible', 'boolean', {'null': False, 'default': True}),
        ],
        'indexes': [('user_id', {}), ('product_id', {}), ('order_item_id', {'unique': True})],
        'foreign_keys': [('user_id', 'users'), ('product_id', 'products'), ('order_item_id', 'order_items')],
        'checks': [('rating >= 1 AND rating <= 5', 'reviews_rating_range')],
    },
    {
        'name': 'notifications',
        'columns': [
            ('user_id', 'bigint', {'null': False}),
            ('type', 'string', {'null': False, 'limit': 50}),
            ('title', 'string', {'null': False, 'limit': 180}),
            ('message', 'text', {'null': False}),
            ('data', 'text'),
            ('read_at', 'datetime'),
        ],
        'indexes': [('user_id', {}), ('read_at', {})],
        'foreign_keys': [('user_id', 'users')],
    },
    {
        'name': 'audit_logs',
        'columns': [
            ('user_id', 'bigint'),
            ('action', 'string', {'null': False, 'limit': 120}),
            ('resource_type', 'string', {'null': False, 'limit': 80}),
            ('resource_id', 'string', {'limit': 120}),
            ('ip_address', 'string', {'limit': 45}),
            ('user_agent', 'text'),
            ('metadata', 'text'),
        ],
        'indexes': [('user_id', {}), ('resource_type', {}), ('action', {})],
        'foreign_keys': [('user_id', 'users')],
    },
    {
        'name': 'idempotency_keys',
        'columns': [
            ('user_id', 'bigint', {'null': False}),
            ('key', 'string', {'null': False, 'limit': 180}),
            ('request_hash', 'string', {'null': False}),
            ('response_status', 'integer', {'null': False, 'default': 200}),
            ('response_body', 'text'),
            ('resource_type', 'string', {'limit': 80}),
            ('resource_id', 'string', {'limit': 120}),
            ('expires_at', 'datetime', {'null': False}),
        ],
        'indexes': [('user_id', {}), (('user_id', 'key'), {'unique': True}), ('expires_at', {})],
        'foreign_keys': [('user_id', 'users')],
        'checks': [('response_status >= 100', 'idempotency_keys_response_status_minimum')],
    },
    {
        'name': 'store_settings',
        'columns': [
            ('setting_key', 'string', {'null': False, 'limit': 120}),
            ('setting_value', 'text', {'null': False}),
            ('updated_by', 'bigint'),
        ],
        'indexes': [('setting_key', {'unique': True}), ('updated_by', {})],
        'foreign_keys': [('updated_by', 'users')],
    },
    {
        'name': 'cancellation_requests',
        'columns': [
            ('order_id', 'bigint', {'null': False}),
            ('requested_by', 'bigint', {'null': False}),
            ('reason', 'text', {'null': False}),
            ('status', 'string', {'null': False, 'default': 'pending', 'limit': 20}),
            ('reviewed_by', 'bigint'),
            ('reviewed_at', 'datetime'),
            ('admin_note', 'text'),
        ],
        'indexes': [('order_id', {}), ('requested_by', {}), ('reviewed_by', {}), ('status', {})],
        'foreign_keys': [('order_id', 'orders'), ('requested_by', 'users'), ('reviewed_by', 'users')],
        'checks': [("status IN ('pending', 'approved', 'rejected')", 'cancellation_requests_status_check')],
    },
    {
        'name': 'refunds',
        'columns': [
            ('payment_id', 'bigint', {'null': False}),
            ('order_id', 'bigint', {'null': False}),
            ('amount', 'integer', {'null': False}),
            ('reason', 'text', {'null': False}),
            ('status', 'string', {'null': False, 'default': 'pending', 'limit': 20}),
            ('processed_by', 'bigint'),
            ('processed_at', 'datetime'),
            ('reference_number', 'string', {'limit': 80}),
            ('notes', 'text'),
        ],
        'indexes': [('payment_id', {}), ('order_id', {}), ('status', {}), ('processed_by', {})],
        'foreign_keys': [('payment_id', 'payments'), ('order_id', 'orders'), ('processed_by', 'users')],
        'checks': [
            ('amount > 0', 'refunds_amount_positive'),
            ("status IN ('pending', 'processed', 'rejected')", 'refunds_status_check'),
        ],
        'comments': ['# D2 refund policy pending final decision; keep database schema neutral and enforce refund rules in transactional service logic.'],
    },
]


def class_name_for_table(table_name: str) -> str:
    return ''.join(part.capitalize() for part in table_name.split('_'))


def ruby_literal(value):
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if value is None:
        return 'nil'
    return repr(value)


def snake_case(value: str) -> str:
    return re.sub(r'(?<!^)(?=[A-Z])', '_', value).lower()


def migration_content(table):
    lines = [
        f"class Create{class_name_for_table(table['name'])} < ActiveRecord::Migration[8.1]",
        '  def change',
        f"    create_table :{table['name']}, force: true do |t|",
    ]
    for column in table['columns']:
        if len(column) == 2:
            name, col_type = column
            opts = {}
        else:
            name, col_type, opts = column
        line = f"      t.{col_type} :{name}"
        for key, value in opts.items():
            if key == 'null':
                line += f", null: {str(value).lower()}"
            elif key == 'default':
                line += f", default: {ruby_literal(value)}"
            elif key == 'limit':
                line += f", limit: {value}"
        lines.append(line)
    lines.append('    end')

    for index in table.get('indexes', []):
        if isinstance(index[0], tuple):
            cols = ', '.join(f':{c}' for c in index[0])
            if index[1].get('unique'):
                lines.append(f"    add_index :{table['name']}, [{cols}], unique: true")
            else:
                lines.append(f"    add_index :{table['name']}, [{cols}]")
        else:
            col = index[0]
            if index[1].get('unique'):
                lines.append(f"    add_index :{table['name']}, :{col}, unique: true")
            else:
                lines.append(f"    add_index :{table['name']}, :{col}")

    for fk in table.get('foreign_keys', []):
        lines.append(f"    add_foreign_key :{table['name']}, :{fk[1]}, on_delete: :restrict")

    for expr, constraint_name in table.get('checks', []):
        lines.append(f"    add_check_constraint :{table['name']}, {expr!r}, name: '{constraint_name}'")

    if 'comments' in table:
        for comment in table['comments']:
            lines.append(f"    {comment}")

    lines.extend(['  end', 'end'])
    return '\n'.join(lines) + '\n'


# generate migration files
for idx, table in enumerate(TABLES, start=1):
    filename = root / 'db' / 'migrate' / f'{202611050000 + idx:014d}_create_{table["name"]}.rb'
    filename.parent.mkdir(parents=True, exist_ok=True)
    filename.write_text(migration_content(table), encoding='utf-8')

# generate model files
model_map = {
    'users': 'User',
    'addresses': 'Address',
    'password_reset_tokens': 'PasswordResetToken',
    'categories': 'Category',
    'products': 'Product',
    'product_images': 'ProductImage',
    'carts': 'Cart',
    'cart_items': 'CartItem',
    'orders': 'Order',
    'order_items': 'OrderItem',
    'payments': 'Payment',
    'payment_proofs': 'PaymentProof',
    'inventory_reservations': 'InventoryReservation',
    'inventory_movements': 'InventoryMovement',
    'shipping_methods': 'ShippingMethod',
    'shipments': 'Shipment',
    'vouchers': 'Voucher',
    'voucher_redemptions': 'VoucherRedemption',
    'wishlists': 'Wishlist',
    'wishlist_items': 'WishlistItem',
    'reviews': 'Review',
    'notifications': 'Notification',
    'audit_logs': 'AuditLog',
    'idempotency_keys': 'IdempotencyKey',
    'store_settings': 'StoreSetting',
    'cancellation_requests': 'CancellationRequest',
    'refunds': 'Refund',
}

README = {
    'User': ['has_secure_password'],
}

ASSOCIations = {
    'User': [
        'has_many :addresses, dependent: :restrict_with_error',
        'has_many :orders, dependent: :restrict_with_error',
        'has_many :carts, dependent: :restrict_with_error',
        'has_many :notifications, dependent: :restrict_with_error',
        'has_many :audit_logs, dependent: :restrict_with_error',
        'has_many :wishlists, dependent: :restrict_with_error',
        'has_many :reviews, dependent: :restrict_with_error',
        'has_many :password_reset_tokens, dependent: :restrict_with_error',
        'has_secure_password',
    ],
    'Address': ['belongs_to :user'],
    'PasswordResetToken': ['belongs_to :user'],
    'Category': ['has_many :products, dependent: :restrict_with_error'],
    'Product': [
        'belongs_to :category',
        'has_many :product_images, dependent: :restrict_with_error',
        'has_many :cart_items, dependent: :restrict_with_error',
        'has_many :order_items, dependent: :restrict_with_error',
        'has_many :inventory_reservations, dependent: :restrict_with_error',
        'has_many :inventory_movements, dependent: :restrict_with_error',
        'has_many :reviews, dependent: :restrict_with_error',
        'has_many :wishlist_items, dependent: :restrict_with_error',
    ],
    'ProductImage': ['belongs_to :product'],
    'Cart': ['belongs_to :user', 'has_many :cart_items, dependent: :restrict_with_error'],
    'CartItem': ['belongs_to :cart', 'belongs_to :product'],
    'Order': [
        'belongs_to :user',
        'belongs_to :shipping_method',
        'has_many :order_items, dependent: :restrict_with_error',
        'has_one :payment, dependent: :restrict_with_error',
        'has_one :shipment, dependent: :restrict_with_error',
        'has_many :inventory_reservations, dependent: :restrict_with_error',
        'has_many :cancellation_requests, dependent: :restrict_with_error',
        'has_many :refunds, dependent: :restrict_with_error',
    ],
    'OrderItem': ['belongs_to :order', 'belongs_to :product', 'has_one :review, dependent: :restrict_with_error'],
    'Payment': [
        'belongs_to :order',
        'belongs_to :verified_by, class_name: "User", foreign_key: :verified_by, optional: true',
        'has_many :payment_proofs, dependent: :restrict_with_error',
        'has_many :refunds, dependent: :restrict_with_error',
    ],
    'PaymentProof': ['belongs_to :payment'],
    'InventoryReservation': ['belongs_to :order', 'belongs_to :product'],
    'InventoryMovement': ['belongs_to :product', 'belongs_to :order, optional: true', 'belongs_to :created_by, class_name: "User", foreign_key: :created_by, optional: true'],
    'ShippingMethod': ['has_many :orders, dependent: :restrict_with_error', 'has_many :shipments, dependent: :restrict_with_error'],
    'Shipment': ['belongs_to :order', 'belongs_to :shipping_method'],
    'Voucher': ['has_many :voucher_redemptions, dependent: :restrict_with_error'],
    'VoucherRedemption': ['belongs_to :voucher', 'belongs_to :user', 'belongs_to :order, optional: true'],
    'Wishlist': ['belongs_to :user', 'has_many :wishlist_items, dependent: :restrict_with_error'],
    'WishlistItem': ['belongs_to :wishlist', 'belongs_to :product'],
    'Review': ['belongs_to :user', 'belongs_to :product', 'belongs_to :order_item'],
    'Notification': ['belongs_to :user', 'self.inheritance_column = :_type_disabled'],
    'AuditLog': ['belongs_to :user, optional: true'],
    'IdempotencyKey': ['belongs_to :user'],
    'StoreSetting': ['belongs_to :updated_by, class_name: "User", foreign_key: :updated_by, optional: true'],
    'CancellationRequest': ['belongs_to :order', 'belongs_to :requested_by, class_name: "User", foreign_key: :requested_by', 'belongs_to :reviewed_by, class_name: "User", foreign_key: :reviewed_by, optional: true'],
    'Refund': ['belongs_to :payment', 'belongs_to :order', 'belongs_to :processed_by, class_name: "User", foreign_key: :processed_by, optional: true'],
}

VALIDATIONS = {
    'User': [
        'validates :name, presence: true, length: { maximum: 150 }',
        'validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }',
        'validates :role, inclusion: { in: %w[admin customer] }',
        'validates :password, length: { minimum: 8 }, if: -> { password.present? }',
    ],
    'Address': [
        'validates :recipient_name, presence: true, length: { maximum: 150 }',
        'validates :phone, presence: true, length: { maximum: 30 }',
        'validates :address_line, presence: true',
        'validates :province, :city, :district, :postal_code, presence: true',
    ],
    'PasswordResetToken': [
        'validates :user, presence: true',
        'validates :token_digest, presence: true',
        'validates :expires_at, presence: true',
    ],
    'Category': ['validates :name, :slug, presence: true', 'validates :slug, uniqueness: true'],
    'Product': [
        'validates :name, :slug, :sku, presence: true',
        'validates :slug, :sku, uniqueness: true',
        'validates :price, :stock_on_hand, :reserved_stock, numericality: { greater_than_or_equal_to: 0 }',
        'validate :reserved_stock_not_exceeding_stock_on_hand',
    ],
    'ProductImage': ['validates :product, :storage_key, presence: true', 'validates :position, numericality: { greater_than_or_equal_to: 0 }'],
    'Cart': ['validates :user, presence: true'],
    'CartItem': ['validates :cart, :product, presence: true', 'validates :quantity, numericality: { only_integer: true, greater_than: 0 }'],
    'Order': ['validates :order_number, :user, :shipping_method, :payment_deadline_at, presence: true', 'validates :status, inclusion: { in: %w[awaiting_payment processing shipped completed cancelled] }', 'validates :subtotal, :discount_amount, :shipping_cost, :total_amount, numericality: { greater_than_or_equal_to: 0 }'],
    'OrderItem': ['validates :order, :product, :product_name_snapshot, :sku_snapshot, presence: true', 'validates :unit_price, :subtotal, numericality: { greater_than_or_equal_to: 0 }', 'validates :quantity, numericality: { only_integer: true, greater_than: 0 }'],
    'Payment': ['validates :order, :payment_method, :amount, presence: true', 'validates :status, inclusion: { in: %w[pending waiting_verification paid rejected expired refunded] }', 'validates :amount, numericality: { greater_than_or_equal_to: 0 }'],
    'PaymentProof': ['validates :payment, :storage_key, :original_filename, :uploaded_at, presence: true', 'validates :status, inclusion: { in: %w[submitted approved rejected] }', 'validates :file_size, numericality: { greater_than_or_equal_to: 0 }'],
    'InventoryReservation': ['validates :order, :product, :quantity, presence: true', 'validates :status, inclusion: { in: %w[reserved converted released] }', 'validates :quantity, numericality: { only_integer: true, greater_than: 0 }'],
    'InventoryMovement': ['validates :product, :movement_type, :quantity, :stock_before, :stock_after, presence: true', 'validates :movement_type, inclusion: { in: %w[stock_in stock_out reservation reservation_release reservation_conversion adjustment return] }'],
    'ShippingMethod': ['validates :name, :estimated_days, presence: true', 'validates :name, uniqueness: true', 'validates :estimated_days, numericality: { only_integer: true, greater_than: 0 }', 'validates :cost, numericality: { greater_than_or_equal_to: 0 }'],
    'Shipment': ['validates :order, :shipping_method, presence: true', 'validates :status, inclusion: { in: %w[not_shipped packed shipped delivered] }'],
    'Voucher': ['validates :code, :discount_type, presence: true', 'validates :code, uniqueness: true', 'validates :discount_type, inclusion: { in: %w[fixed percentage] }', 'validates :discount_value, :minimum_purchase, :maximum_discount, :usage_limit, :per_user_limit, numericality: { greater_than_or_equal_to: 0 }'],
    'VoucherRedemption': ['validates :voucher, :user, presence: true', 'validates :status, inclusion: { in: %w[reserved used released] }'],
    'Wishlist': ['validates :user, presence: true'],
    'WishlistItem': ['validates :wishlist, :product, presence: true'],
    'Review': ['validates :user, :product, :order_item, :rating, presence: true', 'validates :rating, inclusion: { in: 1..5 }'],
    'Notification': ['validates :user, :type, :title, :message, presence: true'],
    'AuditLog': ['validates :action, :resource_type, presence: true'],
    'IdempotencyKey': ['validates :user, :key, :request_hash, :response_status, :expires_at, presence: true', 'validates :key, uniqueness: { scope: :user_id }', 'validates :response_status, numericality: { greater_than_or_equal_to: 100 }'],
    'StoreSetting': ['validates :setting_key, :setting_value, presence: true', 'validates :setting_key, uniqueness: true'],
    'CancellationRequest': ['validates :order, :requested_by, :reason, :status, presence: true', 'validates :status, inclusion: { in: %w[pending approved rejected] }'],
    'Refund': ['validates :payment, :order, :amount, :reason, :status, presence: true', 'validates :status, inclusion: { in: %w[pending processed rejected] }', 'validates :amount, numericality: { greater_than: 0 }'],
}

for table_name, class_name in model_map.items():
    path = root / 'app' / 'models' / f'{snake_case(class_name)}.rb'
    if path.exists():
        continue
    lines = [f'class {class_name} < ApplicationRecord']
    for assoc in ASSOCIations.get(class_name, []):
        lines.append(f'  {assoc}')
    for validation in VALIDATIONS.get(class_name, []):
        lines.append(f'  {validation}')

    if class_name == 'Product':
        lines.extend([
            '',
            '  private',
            '',
            '  def reserved_stock_not_exceeding_stock_on_hand',
            '    return if reserved_stock.nil? || stock_on_hand.nil?',
            '    errors.add(:reserved_stock, "must be less than or equal to stock_on_hand") if reserved_stock > stock_on_hand',
            '  end',
        ])

    if class_name == 'Notification':
        lines.insert(1, '  self.inheritance_column = :_type_disabled')

    lines.append('end')
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')

# seed file
seed_content = dedent('''
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
''')
(root / 'db' / 'seeds.rb').write_text(seed_content.strip() + '\n', encoding='utf-8')

# integrity spec
spec = dedent('''
  # frozen_string_literal: true

  require 'rails_helper'

  RSpec.describe 'database integrity', type: :model do
    it 'keeps auth_sessions out of M2 and uses WAL with busy timeout configured' do
      expect(ActiveRecord::Base.connection.data_source_exists?(:auth_sessions)).to be(false)
      expect(ActiveRecord::Base.connection.select_value('PRAGMA journal_mode').to_s.downcase).to eq('wal')
      expect(ActiveRecord::Base.connection.select_value('PRAGMA busy_timeout').to_i).to eq(5000)
    end

    it 'enforces critical uniqueness and validation constraints' do
      category = Category.create!(name: 'Elektronik', slug: 'elektronik')
      product = Product.create!(category: category, name: 'Keyboard', slug: 'keyboard', sku: 'KB-001', price: 150_000, stock_on_hand: 10, reserved_stock: 2)

      User.create!(name: 'Alice', email: 'alice@example.com', password: 'password123', role: 'customer')
      expect { User.create!(name: 'Alice Duplicate', email: 'alice@example.com', password: 'password123', role: 'customer') }.to raise_error(ActiveRecord::RecordInvalid)
      expect { Product.create!(category: category, name: 'Bad', slug: 'bad-product', sku: 'KB-002', price: -1, stock_on_hand: 5, reserved_stock: 0) }.to raise_error(ActiveRecord::RecordInvalid)

      user = User.create!(name: 'Bob', email: 'bob@example.com', password: 'password123', role: 'customer')
      cart = Cart.create!(user: user)
      expect { CartItem.create!(cart: cart, product: product, quantity: 0) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'enforces foreign key protection for order items' do
      user = User.create!(name: 'Charlie', email: 'charlie@example.com', password: 'password123', role: 'customer')
      shipping_method = ShippingMethod.create!(name: 'Reguler', description: 'Standard', estimated_days: 3, cost: 15000)
      category = Category.create!(name: 'Gadget', slug: 'gadget')
      product = Product.create!(category: category, name: 'Mouse', slug: 'mouse', sku: 'MS-001', price: 80_000, stock_on_hand: 10, reserved_stock: 0)
      order = Order.create!(order_number: 'ORD-1001', user: user, shipping_method: shipping_method, payment_deadline_at: 1.day.from_now, status: 'awaiting_payment', subtotal: 100_000, discount_amount: 0, shipping_cost: 15_000, total_amount: 115_000)

      expect do
        OrderItem.create!(order_id: 9_999_999, product: product, product_name_snapshot: 'Mouse', sku_snapshot: 'MS-001', unit_price: 80_000, quantity: 1, subtotal: 80_000)
      end.to raise_error(ActiveRecord::StatementInvalid)

      expect(order.reload).to be_present
    end
  end
''')
(root / 'spec' / 'models').mkdir(parents=True, exist_ok=True)
(root / 'spec' / 'models' / 'database_integrity_spec.rb').write_text(spec.strip() + '\n', encoding='utf-8')

print('schema generated')
