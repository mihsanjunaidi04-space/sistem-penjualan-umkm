# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin seed', type: :service do
  around do |example|
    original_email = ENV['ADMIN_EMAIL']
    original_password = ENV['ADMIN_INITIAL_PASSWORD']
    ENV['ADMIN_EMAIL'] = nil
    ENV['ADMIN_INITIAL_PASSWORD'] = nil
    example.run
  ensure
    ENV['ADMIN_EMAIL'] = original_email
    ENV['ADMIN_INITIAL_PASSWORD'] = original_password
  end

  describe 'without credentials' do
    before do
      User.where(email: 'admin@example.com').delete_all
    end

    it 'does not create an admin user' do
      expect {
        load Rails.root.join('db/seeds.rb')
      }.not_to change(User, :count)
    end

    it 'does not create any admin user' do
      load Rails.root.join('db/seeds.rb')
      expect(User.where(role: 'admin')).to be_empty
    end
  end

  describe 'with only ADMIN_EMAIL' do
    let(:email) { 'admin-email-only@example.com' }

    before do
      User.where(email: email).delete_all
      ENV['ADMIN_EMAIL'] = email
      ENV['ADMIN_INITIAL_PASSWORD'] = nil
    end

    it 'does not create an admin user' do
      expect {
        load Rails.root.join('db/seeds.rb')
      }.not_to change { User.where(email: email).count }
    end
  end

  describe 'with only ADMIN_INITIAL_PASSWORD' do
    before do
      ENV['ADMIN_EMAIL'] = nil
      ENV['ADMIN_INITIAL_PASSWORD'] = 'TestPassword123!'
    end

    it 'does not create an admin user' do
      expect {
        load Rails.root.join('db/seeds.rb')
      }.not_to change { User.where(role: 'admin').count }
    end
  end

  describe 'with credentials' do
    let(:email) { 'admin@example.com' }
    let(:password) { 'TestPassword123!' }

    before do
      User.where(email: email).delete_all
      ENV['ADMIN_EMAIL'] = email
      ENV['ADMIN_INITIAL_PASSWORD'] = password
    end

    it 'creates an admin user' do
      expect {
        load Rails.root.join('db/seeds.rb')
      }.to change(User, :count).by(1)
    end

    it 'creates admin with correct attributes' do
      load Rails.root.join('db/seeds.rb')
      admin = User.find_by(email: email)
      expect(admin).to be_present
      expect(admin.role).to eq('admin')
      expect(admin.is_active).to be(true)
      expect(admin.authenticate(password)).to eq(admin)
    end

    it 'does not reset existing admin password' do
      load Rails.root.join('db/seeds.rb')
      admin = User.find_by(email: email)
      original_password_digest = admin.password_digest

      ENV['ADMIN_INITIAL_PASSWORD'] = 'DifferentPassword123!'
      load Rails.root.join('db/seeds.rb')

      admin.reload
      expect(admin.password_digest).to eq(original_password_digest)
    end

    it 'does not change existing admin role or active status' do
      load Rails.root.join('db/seeds.rb')
      admin = User.find_by(email: email)
      admin.update!(role: 'customer', is_active: false)
      admin.reload

      ENV['ADMIN_INITIAL_PASSWORD'] = 'AnotherPassword123!'
      load Rails.root.join('db/seeds.rb')

      admin.reload
      expect(admin.role).to eq('customer')
      expect(admin.is_active).to be(false)
    end
  end
end
