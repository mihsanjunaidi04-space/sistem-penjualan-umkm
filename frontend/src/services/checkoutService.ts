import api from './api'
import type { AddressResponse, CartResponse, CheckoutResponse, ShippingMethodResponse } from '../types/checkout'

export const checkoutService = {
  getCart: async (): Promise<CartResponse> => (await api.get('/cart')) as unknown as CartResponse,
  addItem: async (productId: number, quantity: number): Promise<CartResponse> => (await api.post('/cart/items', { product_id: productId, quantity })) as unknown as CartResponse,
  updateItem: async (itemId: number, quantity: number): Promise<CartResponse> => (await api.patch(`/cart/items/${itemId}`, { quantity })) as unknown as CartResponse,
  removeItem: async (itemId: number): Promise<CartResponse> => (await api.delete(`/cart/items/${itemId}`)) as unknown as CartResponse,
  clear: async (): Promise<CartResponse> => (await api.delete('/cart/items')) as unknown as CartResponse,
  getAddresses: async (): Promise<AddressResponse> => (await api.get('/customer/addresses')) as unknown as AddressResponse,
  getShippingMethods: async (): Promise<ShippingMethodResponse> => (await api.get('/shipping-methods')) as unknown as ShippingMethodResponse,
  checkout: async (addressId: number, shippingMethodId: number, notes: string, idempotencyKey: string): Promise<CheckoutResponse> => (await api.post('/checkout', { address_id: addressId, shipping_method_id: shippingMethodId, customer_notes: notes }, { headers: { 'Idempotency-Key': idempotencyKey } })) as unknown as CheckoutResponse,
}
