export interface Category {
  id: number
  name: string
  slug: string
  description: string | null
  is_active: boolean
  products_count?: number
}

export interface ProductImage { id: number; alt_text: string | null; position: number; url: string }

export interface Product {
  id: number; name: string; slug: string; sku: string; description: string | null
  price: number; stock_on_hand: number; reserved_stock: number; available_stock: number
  is_active: boolean; category: Pick<Category, 'id' | 'name' | 'slug'>; images: ProductImage[]
}

export interface ProductListResponse { success: boolean; data: { products: Product[]; pagination: { page: number; per_page: number; total: number; total_pages: number } }; message: string }
export interface CategoryListResponse { success: boolean; data: { categories: Category[] }; message: string }
export interface ProductDetailResponse { success: boolean; data: { product: Product }; message: string }
export interface CategoryDetailResponse { success: boolean; data: { category: Category; products: Product[] }; message: string }
export interface CategoryPayload { name: string; slug?: string; description: string; is_active: boolean }
export interface ProductPayload { category_id: number; name: string; slug?: string; sku: string; description: string; price: number; stock_on_hand: number; reserved_stock: number; is_active: boolean }
export interface AdminCategoryResponse { success: boolean; data: { category: Category }; message: string }
export interface AdminProductResponse { success: boolean; data: { product: Product }; message: string }
