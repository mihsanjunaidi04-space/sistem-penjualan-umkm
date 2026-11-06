import api from './api'
import type { AdminPaymentsResponse, CustomerOrder, CustomerOrderResponse, Payment } from '../types/payment'
import type { AdminOrdersResponse, CancellationResponse } from '../types/order'

export const paymentService = {
  getOrders: async (): Promise<{ data: { orders: CustomerOrder[] } }> => (await api.get('/customer/orders')) as unknown as { data: { orders: CustomerOrder[] } },
  getOrder: async (id: number): Promise<CustomerOrderResponse> => (await api.get(`/customer/orders/${id}`)) as unknown as CustomerOrderResponse,
  uploadProof: async (orderId: number, file: File): Promise<{ data: { payment: Payment } }> => { const form = new FormData(); form.append('proof', file); return (await api.post(`/customer/orders/${orderId}/payment-proof`, form, { headers: { 'Content-Type': 'multipart/form-data' } })) as unknown as { data: { payment: Payment } } },
  listPending: async (): Promise<AdminPaymentsResponse> => (await api.get('/admin/payments')) as unknown as AdminPaymentsResponse,
  approve: async (id: number): Promise<void> => { await api.post(`/admin/payments/${id}/approve`) },
  reject: async (id: number, reason: string): Promise<void> => { await api.post(`/admin/payments/${id}/reject`, { reason }) },
  downloadProof: async (id: number, proofId: number): Promise<Blob> => (await api.get(`/admin/payments/${id}/proofs/${proofId}`, { responseType: 'blob' })) as unknown as Blob,
  requestCancellation: async (orderId: number, reason: string): Promise<void> => { await api.post(`/customer/orders/${orderId}/cancellation-requests`, { reason }) },
  listOrders: async (status?: string, query?: string): Promise<AdminOrdersResponse> => (await api.get('/admin/orders', { params: { status, q: query } })) as unknown as AdminOrdersResponse,
  createShipment: async (orderId: number): Promise<void> => { await api.post(`/admin/orders/${orderId}/shipments`) },
  packShipment: async (id: number): Promise<void> => { await api.patch(`/admin/shipments/${id}/pack`) },
  shipShipment: async (id: number, trackingNumber: string): Promise<void> => { await api.patch(`/admin/shipments/${id}/ship`, { tracking_number: trackingNumber }) },
  deliverShipment: async (id: number): Promise<void> => { await api.patch(`/admin/shipments/${id}/deliver`) },
  listCancellations: async (): Promise<CancellationResponse> => (await api.get('/admin/cancellation-requests')) as unknown as CancellationResponse,
  approveCancellation: async (id: number): Promise<void> => { await api.post(`/admin/cancellation-requests/${id}/approve`) },
  rejectCancellation: async (id: number, note: string): Promise<void> => { await api.post(`/admin/cancellation-requests/${id}/reject`, { admin_note: note }) },
}
