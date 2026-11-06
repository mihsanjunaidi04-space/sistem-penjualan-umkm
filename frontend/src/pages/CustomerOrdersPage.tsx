import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { paymentService } from '../services/paymentService'
import type { CustomerOrder } from '../types/payment'

export function CustomerOrdersPage() {
  const [orders, setOrders] = useState<CustomerOrder[]>([]); const [error, setError] = useState('');
  useEffect(() => { void paymentService.getOrders().then((response) => setOrders(response.data.orders)).catch((reason: unknown) => setError(reason instanceof Error ? reason.message : 'Pesanan gagal dimuat.')) }, [])
  return <div className="container"><div className="section-heading"><div><p className="eyebrow">Customer</p><h1>Pesanan saya</h1></div></div>{error ? <div className="form-error">{error}</div> : null}{orders.length === 0 ? <div className="panel-card state-card">Belum ada pesanan.</div> : <div className="admin-list">{orders.map((order) => <Link className="panel-card admin-list__row" to={`/customer/orders/${order.id}/payment`} key={order.id}><div><strong>{order.order_number}</strong><small>{order.status} · Pembayaran {order.payment?.status ?? 'pending'} · Pengiriman {order.shipment?.status ?? 'belum dibuat'}{order.shipment?.tracking_number ? ` · Resi ${order.shipment.tracking_number}` : ''}</small></div><strong>Rp {order.total_amount.toLocaleString('id-ID')}</strong></Link>)}</div>}</div>
}
