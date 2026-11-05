export interface CartItem {
  id: number
  quantity: number
  product: { id: number; name: string; slug: string; sku: string; price: number; is_active: boolean; category_active: boolean; available_stock: number }
  subtotal: number
  available: boolean
}

export interface CartResponse { success: boolean; data: { id: number; items: CartItem[]; subtotal: number; item_count: number }; message: string }
export interface Address { id: number; recipient_name: string; phone: string; address_line: string; province: string; city: string; district: string; postal_code: string; notes: string | null; is_default: boolean }
export interface AddressResponse { success: boolean; data: { addresses: Address[] }; message: string }
export interface ShippingMethod { id: number; name: string; description: string | null; estimated_days: number; cost: number }
export interface ShippingMethodResponse { success: boolean; data: { shipping_methods: ShippingMethod[] }; message: string }
export interface OrderItem { product_name: string; sku: string; unit_price: number; quantity: number; subtotal: number }
export interface CheckoutOrder { id: number; order_number: string; status: string; subtotal: number; shipping_cost: number; total_amount: number; payment_deadline_at: string; shipping_method: { id: number; name: string; cost: number }; items: OrderItem[] }
export interface CheckoutResponse { success: boolean; data: { order: CheckoutOrder }; message: string }
