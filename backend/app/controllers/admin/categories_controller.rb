module Admin
  class CategoriesController < ApplicationController
    before_action :require_admin!

    def index
      categories = Category.order(:name)
      render json: { success: true, data: { categories: categories.map { |category| serialize(category) } }, message: 'Daftar kategori berhasil diambil.' }
    end

    def create
      category = Category.new(category_params)
      category.slug = slug_for(category.name) if category.slug.blank?
      if category.save
        render json: { success: true, data: { category: serialize(category) }, message: 'Kategori berhasil dibuat.' }, status: :created
      else
        render_error(:unprocessable_content, 'VALIDATION_ERROR', 'Data kategori tidak valid.', category.errors.to_hash)
      end
    end

    def update
      category = Category.find(params[:id])
      attributes = category_params
      attributes[:slug] = slug_for(attributes[:name]) if attributes[:slug].blank? && attributes[:name].present?
      if category.update(attributes)
        render json: { success: true, data: { category: serialize(category) }, message: 'Kategori berhasil diubah.' }
      else
        render_error(:unprocessable_content, 'VALIDATION_ERROR', 'Data kategori tidak valid.', category.errors.to_hash)
      end
    rescue ActiveRecord::RecordNotFound
      render_error(:not_found, 'CATEGORY_NOT_FOUND', 'Kategori tidak ditemukan.')
    end

    private

    def category_params
      params.permit(:name, :slug, :description, :is_active)
    end

    def slug_for(value)
      value.to_s.parameterize
    end

    def serialize(category)
      { id: category.id, name: category.name, slug: category.slug, description: category.description, is_active: category.is_active, products_count: category.products.count }
    end
  end
end
