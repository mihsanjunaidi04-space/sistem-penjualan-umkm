import api from './api'
import type { AdminCategoryResponse, AdminProductResponse, CategoryDetailResponse, CategoryListResponse, CategoryPayload, ProductDetailResponse, ProductListResponse, ProductPayload } from '../types/catalog'

export const catalogService = {
  listCategories: async (): Promise<CategoryListResponse> => (await api.get('/categories')) as unknown as CategoryListResponse,
  getCategory: async (slug: string): Promise<CategoryDetailResponse> => (await api.get(`/categories/${slug}`)) as unknown as CategoryDetailResponse,
  listProducts: async (params?: { q?: string; category?: string; page?: number; per_page?: number }): Promise<ProductListResponse> => (await api.get('/products', { params })) as unknown as ProductListResponse,
  getProduct: async (slug: string): Promise<ProductDetailResponse> => (await api.get(`/products/${slug}`)) as unknown as ProductDetailResponse,
  adminListCategories: async (): Promise<CategoryListResponse> => (await api.get('/admin/categories')) as unknown as CategoryListResponse,
  createCategory: async (payload: CategoryPayload): Promise<AdminCategoryResponse> => (await api.post('/admin/categories', payload)) as unknown as AdminCategoryResponse,
  updateCategory: async (id: number, payload: Partial<CategoryPayload>): Promise<AdminCategoryResponse> => (await api.patch(`/admin/categories/${id}`, payload)) as unknown as AdminCategoryResponse,
  adminListProducts: async (params?: { q?: string; category_id?: number }): Promise<ProductListResponse> => (await api.get('/admin/products', { params })) as unknown as ProductListResponse,
  createProduct: async (payload: ProductPayload): Promise<AdminProductResponse> => (await api.post('/admin/products', payload)) as unknown as AdminProductResponse,
  updateProduct: async (id: number, payload: Partial<ProductPayload>): Promise<AdminProductResponse> => (await api.patch(`/admin/products/${id}`, payload)) as unknown as AdminProductResponse,
  uploadImage: async (id: number, file: File, altText: string): Promise<void> => { const form = new FormData(); form.append('file', file); form.append('alt_text', altText); await api.post(`/admin/products/${id}/images`, form, { headers: { 'Content-Type': 'multipart/form-data' } }) },
  deleteImage: async (productId: number, imageId: number): Promise<void> => { await api.delete(`/admin/products/${productId}/images/${imageId}`) },
}
