import { useEffect, useState } from 'react'
import type { ChangeEvent, FormEvent } from 'react'
import { catalogService } from '../services/catalogService'
import type { Category, CategoryPayload, Product, ProductPayload } from '../types/catalog'

const emptyCategory: CategoryPayload = { name: '', description: '', is_active: true }
const emptyProduct: ProductPayload = { category_id: 0, name: '', sku: '', description: '', price: 0, stock_on_hand: 0, reserved_stock: 0, is_active: true }

export function AdminCatalogPage() {
  const [categories, setCategories] = useState<Category[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [categoryForm, setCategoryForm] = useState<CategoryPayload>(emptyCategory)
  const [productForm, setProductForm] = useState<ProductPayload>(emptyProduct)
  const [editingCategory, setEditingCategory] = useState<number | null>(null)
  const [editingProduct, setEditingProduct] = useState<number | null>(null)
  const [selectedImage, setSelectedImage] = useState<File | null>(null)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)

  const load = async () => {
    setLoading(true)
    try {
      const [categoryResponse, productResponse] = await Promise.all([catalogService.adminListCategories(), catalogService.adminListProducts()])
      setCategories(categoryResponse.data.categories); setProducts(productResponse.data.products)
      setProductForm((current) => current.category_id ? current : { ...emptyProduct, category_id: categoryResponse.data.categories[0]?.id ?? 0 })
    } catch (reason) { setError(reason instanceof Error ? reason.message : 'Data katalog gagal dimuat.') } finally { setLoading(false) }
  }

  useEffect(() => { void load() }, [])

  const submitCategory = async (event: FormEvent) => {
    event.preventDefault(); setError(''); setMessage('')
    try { if (editingCategory) await catalogService.updateCategory(editingCategory, categoryForm); else await catalogService.createCategory(categoryForm); setCategoryForm(emptyCategory); setEditingCategory(null); setMessage('Kategori berhasil disimpan.'); await load() } catch (reason) { setError(reason instanceof Error ? reason.message : 'Kategori gagal disimpan.') }
  }

  const submitProduct = async (event: FormEvent) => {
    event.preventDefault(); setError(''); setMessage('')
    try { const response = editingProduct ? await catalogService.updateProduct(editingProduct, productForm) : await catalogService.createProduct(productForm); if (selectedImage) await catalogService.uploadImage(response.data.product.id, selectedImage, productForm.name); setProductForm({ ...emptyProduct, category_id: categories[0]?.id ?? 0 }); setSelectedImage(null); setEditingProduct(null); setMessage('Produk berhasil disimpan.'); await load() } catch (reason) { setError(reason instanceof Error ? reason.message : 'Produk gagal disimpan.') }
  }

  const editCategory = (category: Category) => { setEditingCategory(category.id); setCategoryForm({ name: category.name, description: category.description ?? '', is_active: category.is_active }) }
  const editProduct = (product: Product) => { setEditingProduct(product.id); setProductForm({ category_id: product.category.id, name: product.name, slug: product.slug, sku: product.sku, description: product.description ?? '', price: product.price, stock_on_hand: product.stock_on_hand, reserved_stock: product.reserved_stock, is_active: product.is_active }) }
  const setNumber = (field: 'price' | 'stock_on_hand' | 'reserved_stock', event: ChangeEvent<HTMLInputElement>) => setProductForm((current) => ({ ...current, [field]: Number(event.target.value) }))
  const cancelCategory = () => { setEditingCategory(null); setCategoryForm(emptyCategory) }
  const cancelProduct = () => { setEditingProduct(null); setProductForm({ ...emptyProduct, category_id: categories[0]?.id ?? 0 }); setSelectedImage(null) }
  const removeImage = async (productId: number, imageId: number) => { setError(''); try { await catalogService.deleteImage(productId, imageId); setMessage('Gambar berhasil dihapus.'); await load() } catch (reason) { setError(reason instanceof Error ? reason.message : 'Gambar gagal dihapus.') } }

  return <div className="catalog-admin">{message ? <div className="success-message">{message}</div> : null}{error ? <div className="form-error">{error}</div> : null}{loading ? <div className="panel-card state-card">Memuat data katalog...</div> : null}<div className="admin-catalog-grid">
    <section className="panel-card"><div className="section-heading"><div><p className="eyebrow">Kategori</p><h2>{editingCategory ? 'Edit kategori' : 'Tambah kategori'}</h2></div></div><form className="catalog-form" onSubmit={(event) => void submitCategory(event)}><label>Nama<input required maxLength={150} value={categoryForm.name} onChange={(event) => setCategoryForm({ ...categoryForm, name: event.target.value })} /></label><label>Deskripsi<textarea maxLength={2000} value={categoryForm.description} onChange={(event) => setCategoryForm({ ...categoryForm, description: event.target.value })} /></label><label className="checkbox-field"><input type="checkbox" checked={categoryForm.is_active} onChange={(event) => setCategoryForm({ ...categoryForm, is_active: event.target.checked })} /> Aktif</label><div className="form-actions"><button type="submit">Simpan</button>{editingCategory ? <button type="button" className="button-secondary" onClick={cancelCategory}>Batal</button> : null}</div></form><div className="admin-list">{categories.map((category) => <div className="admin-list__row" key={category.id}><div><strong>{category.name}</strong><small>{category.products_count ?? 0} produk · {category.is_active ? 'Aktif' : 'Nonaktif'}</small></div><button type="button" className="button-link" onClick={() => editCategory(category)}>Edit</button></div>)}</div></section>
    <section className="panel-card"><div className="section-heading"><div><p className="eyebrow">Produk</p><h2>{editingProduct ? 'Edit produk' : 'Tambah produk'}</h2></div></div><form className="catalog-form" onSubmit={(event) => void submitProduct(event)}><label>Nama<input required maxLength={180} value={productForm.name} onChange={(event) => setProductForm({ ...productForm, name: event.target.value })} /></label><label>SKU<input required maxLength={120} value={productForm.sku} onChange={(event) => setProductForm({ ...productForm, sku: event.target.value })} /></label><label>Kategori<select required value={productForm.category_id} onChange={(event) => setProductForm({ ...productForm, category_id: Number(event.target.value) })}>{categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label><div className="form-row"><label>Harga<input required min="0" type="number" value={productForm.price} onChange={(event) => setNumber('price', event)} /></label><label>Stok<input required min="0" type="number" value={productForm.stock_on_hand} onChange={(event) => setNumber('stock_on_hand', event)} /></label></div><label>Deskripsi<textarea maxLength={5000} value={productForm.description} onChange={(event) => setProductForm({ ...productForm, description: event.target.value })} /></label><label>Gambar<input type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => setSelectedImage(event.target.files?.[0] ?? null)} /></label><label className="checkbox-field"><input type="checkbox" checked={productForm.is_active} onChange={(event) => setProductForm({ ...productForm, is_active: event.target.checked })} /> Aktif</label><div className="form-actions"><button type="submit">Simpan</button>{editingProduct ? <button type="button" className="button-secondary" onClick={cancelProduct}>Batal</button> : null}</div></form><div className="admin-list">{products.map((product) => <div className="admin-list__row" key={product.id}><div><strong>{product.name}</strong><small>{product.category.name} · {product.is_active ? `Aktif · stok ${product.available_stock}` : 'Nonaktif'}</small>{product.images.length ? <div className="image-admin-list">{product.images.map((image) => <span key={image.id}><img src={image.url} alt={image.alt_text ?? product.name} /><button type="button" className="button-link" onClick={() => void removeImage(product.id, image.id)}>Hapus gambar</button></span>)}</div> : null}</div><button type="button" className="button-link" onClick={() => editProduct(product)}>Edit</button></div>)}</div></section>
  </div></div>
}
