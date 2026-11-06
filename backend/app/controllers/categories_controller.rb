class CategoriesController < ApplicationController
  def index
    categories = Category.where(is_active: true).order(:name)
    render json: { success: true, data: { categories: categories.map { |category| serialize_category(category) } }, message: "Daftar kategori berhasil diambil." }
  end

  def show
    category = Category.where(is_active: true).find_by!(slug: params[:slug])
    products = category.products.where(is_active: true).order(:name)
    render json: {
      success: true,
      data: {
        category: serialize_category(category),
        products: products.map { |product| ProductsController.serialize_product(product, request) }
      },
      message: "Detail kategori berhasil diambil."
    }
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "CATEGORY_NOT_FOUND", "Kategori tidak ditemukan.")
  end

  private

  def serialize_category(category)
    { id: category.id, name: category.name, slug: category.slug, description: category.description, is_active: category.is_active }
  end
end
