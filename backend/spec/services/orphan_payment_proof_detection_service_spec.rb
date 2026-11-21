require 'rails_helper'
require 'tmpdir'
require 'pathname'

RSpec.describe OrphanPaymentProofDetectionService, type: :service do
  around do |example|
    Dir.mktmpdir('orphan-proof-detection-') do |dir|
      @tmp_root = Pathname.new(dir)
      example.run
    end
  end

  let(:root) { @tmp_root }
  let(:valid_key) { ('a1b2c3d4e5f678901234567890abcdef' * 2) + '.jpg' }
  let(:invalid_key) { 'short.jpg' }
  let(:cursor) { nil }

  def write_file(name, mtime: Time.current)
    path = root.join(name)
    File.binwrite(path, 'fake content')
    stamp = mtime.respond_to?(:to_time) ? mtime.to_time : mtime
    File.utime(stamp, stamp, path)
    path
  end

  def key_for(index)
    format('%064d', index) + '.jpg'
  end

  def create_referenced_proof(storage_key)
    user = User.create!(
      name: 'Test User',
      email: "test-#{SecureRandom.hex(4)}@example.com",
      password: 'password123',
      role: 'customer'
    )
    shipping_method = ShippingMethod.create!(
      name: "Reguler-#{SecureRandom.hex(4)}",
      description: 'Regular',
      estimated_days: 3,
      cost: 5000,
      is_active: true
    )
    order = Order.create!(
      order_number: "ORD-#{SecureRandom.hex(4)}",
      user: user,
      shipping_method: shipping_method,
      status: 'completed',
      subtotal: 10000,
      discount_amount: 0,
      shipping_cost: 5000,
      total_amount: 15000,
      payment_deadline_at: 12.hours.from_now
    )
    payment = Payment.create!(
      order: order,
      payment_method: 'bank_transfer',
      amount: 15000,
      status: 'paid'
    )
    PaymentProof.create!(
      payment: payment,
      storage_key: storage_key,
      original_filename: 'proof.jpg',
      mime_type: 'image/jpeg',
      file_size: 1024,
      status: 'submitted',
      uploaded_at: 2.days.ago
    )
  end

  describe '.call' do
    context 'root directory kosong' do
      it 'mengembalikan nol semua statistik dan has_more false' do
        result = described_class.call(cursor: cursor, root: root)

        expect(result[:scanned]).to eq(0)
        expect(result[:processed]).to eq(0)
        expect(result[:failed]).to eq(0)
        expect(result[:orphaned]).to eq(0)
        expect(result[:referenced]).to eq(0)
        expect(result[:too_recent]).to eq(0)
        expect(result[:invalid_name]).to eq(0)
        expect(result[:symlink]).to eq(0)
        expect(result[:invalid_type]).to eq(0)
        expect(result[:has_more]).to eq(false)
        expect(result[:next_cursor]).to eq(nil)
      end
    end

    context 'root directory tidak ada' do
      it 'mengembalikan nol semua statistik dan has_more false' do
        missing = root.join('does-not-exist')
        result = described_class.call(cursor: cursor, root: missing)

        expect(result[:scanned]).to eq(0)
        expect(result[:processed]).to eq(0)
        expect(result[:failed]).to eq(0)
        expect(result[:has_more]).to eq(false)
      end
    end

    context 'file regular dengan nama valid' do
      it 'terdeteksi sebagai satu file reguler dan . / .. tidak dihitung' do
        write_file(valid_key, mtime: 2.days.ago)

        result = described_class.call(cursor: cursor, root: root)

        expect(result[:scanned]).to eq(1)
        expect(result[:invalid_name]).to eq(0)
        expect(result[:invalid_type]).to eq(0)
        expect(result[:symlink]).to eq(0)
        expect(result[:orphaned]).to eq(1)
        expect(result[:processed]).to eq(1)
      end
    end

    context 'file regular dengan nama invalid (pendek)' do
      it 'terdeteksi sebagai invalid_name' do
        write_file(invalid_key, mtime: 2.days.ago)

        result = described_class.call(cursor: cursor, root: root)

        expect(result[:scanned]).to eq(1)
        expect(result[:invalid_name]).to eq(1)
        expect(result[:processed]).to eq(1)
        expect(result[:orphaned]).to eq(0)
      end
    end

    context 'directory di dalam storage root' do
      it 'terdeteksi sebagai invalid_type' do
        root.join('subdir').mkpath

        result = described_class.call(cursor: cursor, root: root)

        expect(result[:scanned]).to eq(1)
        expect(result[:invalid_type]).to eq(1)
        expect(result[:processed]).to eq(1)
      end
    end

    context 'symlink ke file yang exist' do
      it 'terdeteksi sebagai symlink tanpa mengikuti target' do
        begin
          File.symlink('fake_content', root.join(valid_key))
        rescue NotImplementedError, Errno::EACCES, Errno::EPERM
          skip 'Symlink creation not permitted on this platform'
        end

        result = described_class.call(cursor: cursor, root: root)

        expect(result[:symlink]).to eq(1)
        expect(result[:processed]).to eq(1)
      end
    end

    context 'file tepat 24 jam (mtime = cutoff)' do
      it 'lolos usia minimum (eligible -> orphaned)' do
        write_file(valid_key, mtime: Time.current - 1.day)

        result = described_class.call(cursor: cursor, root: root)

        expect(result[:too_recent]).to eq(0)
        expect(result[:orphaned] + result[:referenced]).to be >= 1
      end
    end

    context 'file lebih muda dari 24 jam' do
      it 'terlalu muda (too_recent) dan dihitung processed' do
        write_file(valid_key, mtime: Time.current)

        result = described_class.call(cursor: cursor, root: root)

        expect(result[:too_recent]).to eq(1)
        expect(result[:processed]).to eq(1)
        expect(result[:orphaned]).to eq(0)
      end
    end

    context 'file lebih tua dari 24 jam' do
      it 'eligible (lolos usia minimum) dan menjadi orphaned' do
        write_file(valid_key, mtime: 2.days.ago)

        result = described_class.call(cursor: cursor, root: root)

        expect(result[:too_recent]).to eq(0)
        expect(result[:orphaned]).to eq(1)
      end
    end

    context 'file yang direferensikan DB' do
      it 'terdeteksi sebagai referenced' do
        create_referenced_proof(valid_key)
        write_file(valid_key, mtime: 2.days.ago)

        result = described_class.call(cursor: cursor, root: root)

        expect(result[:referenced]).to eq(1)
        expect(result[:orphaned]).to eq(0)
        expect(result[:processed]).to eq(1)
      end
    end

    context 'file orphan (tidak ada DB reference)' do
      it 'terdeteksi sebagai orphaned' do
        write_file(valid_key, mtime: 2.days.ago)

        result = described_class.call(cursor: cursor, root: root)

        expect(result[:orphaned]).to eq(1)
        expect(result[:referenced]).to eq(0)
        expect(result[:processed]).to eq(1)
      end
    end

    context 'hidden file dengan nama invalid' do
      it 'tidak dikecualikan dan diklasifikasikan invalid_name' do
        write_file('.hidden.jpg', mtime: 2.days.ago)

        result = described_class.call(cursor: cursor, root: root)

        expect(result[:scanned]).to eq(1)
        expect(result[:invalid_name]).to eq(1)
        expect(result[:processed]).to eq(1)
      end
    end

    context 'invariant statistik pada direktori campuran' do
      it 'processed = sum 6 kategori sukses dan scanned = processed + failed' do
        write_file(valid_key, mtime: 2.days.ago)
        write_file(invalid_key, mtime: 2.days.ago)
        write_file('.hidden.jpg', mtime: 2.days.ago)
        root.join('subdir').mkpath
        write_file(key_for(500), mtime: Time.current)

        result = described_class.call(cursor: cursor, root: root)

        sum_kelas = result[:orphaned] + result[:referenced] + result[:too_recent] +
                    result[:invalid_name] + result[:symlink] + result[:invalid_type]

        expect(result[:processed]).to eq(sum_kelas)
        expect(result[:scanned]).to eq(result[:processed] + result[:failed])
      end
    end

    context 'pagination' do
      it 'tepat 100 entri tanpa sisa => has_more false' do
        100.times { |i| write_file(key_for(i), mtime: 2.days.ago) }

        result = described_class.call(cursor: cursor, root: root)

        expect(result[:scanned]).to eq(100)
        expect(result[:processed]).to eq(100)
        expect(result[:orphaned]).to eq(100)
        expect(result[:has_more]).to eq(false)
        expect(result[:next_cursor]).to eq(key_for(99))
      end

      it '101 entri => has_more true dan sisa diproses lewat cursor' do
        101.times { |i| write_file(key_for(i), mtime: 2.days.ago) }

        first = described_class.call(cursor: cursor, root: root)
        expect(first[:scanned]).to eq(100)
        expect(first[:has_more]).to eq(true)
        expect(first[:next_cursor]).to eq(key_for(99))

        second = described_class.call(cursor: first[:next_cursor], root: root)
        expect(second[:scanned]).to eq(1)
        expect(second[:orphaned]).to eq(1)
        expect(second[:has_more]).to eq(false)
      end
    end

    context 'error database' do
      before do
        allow(PaymentProof).to receive(:where).and_call_original
      end

      it 'error pada entri ke-1 => failed, stop, has_more true, retry berhasil' do
        3.times { |i| write_file(key_for(i), mtime: 2.days.ago) }

        allow(PaymentProof).to receive(:where)
          .with(storage_key: key_for(0))
          .and_raise(ActiveRecord::StatementInvalid.new('boom'))

        first = described_class.call(cursor: cursor, root: root)
        expect(first[:scanned]).to eq(1)
        expect(first[:processed]).to eq(0)
        expect(first[:failed]).to eq(1)
        expect(first[:orphaned]).to eq(0)
        expect(first[:next_cursor]).to eq(nil)
        expect(first[:has_more]).to eq(true)

        allow(PaymentProof).to receive(:where)
          .with(storage_key: key_for(0))
          .and_call_original

        retry_result = described_class.call(cursor: first[:next_cursor], root: root)
        expect(retry_result[:scanned]).to eq(3)
        expect(retry_result[:orphaned]).to eq(3)
        expect(retry_result[:failed]).to eq(0)
      end

      it 'error pada entri pertama halaman lanjutan mempertahankan cursor input' do
        3.times { |i| write_file(key_for(i), mtime: 2.days.ago) }

        allow(PaymentProof).to receive(:where)
          .with(storage_key: key_for(1))
          .and_raise(ActiveRecord::StatementInvalid.new('boom'))

        result = described_class.call(cursor: key_for(0), root: root)
        expect(result[:scanned]).to eq(1)
        expect(result[:processed]).to eq(0)
        expect(result[:failed]).to eq(1)
        expect(result[:next_cursor]).to eq(key_for(0))
        expect(result[:has_more]).to eq(true)

        allow(PaymentProof).to receive(:where)
          .with(storage_key: key_for(1))
          .and_call_original

        retry_result = described_class.call(cursor: result[:next_cursor], root: root)
        expect(retry_result[:scanned]).to eq(2)
        expect(retry_result[:orphaned]).to eq(2)
        expect(retry_result[:failed]).to eq(0)
        expect(retry_result[:next_cursor]).to eq(key_for(2))
      end

      it 'error pada entri ke-50 => next_cursor entri ke-49, retry dari ke-50' do
        100.times { |i| write_file(key_for(i), mtime: 2.days.ago) }

        allow(PaymentProof).to receive(:where)
          .with(storage_key: key_for(49))
          .and_raise(ActiveRecord::StatementInvalid.new('boom'))

        first = described_class.call(cursor: cursor, root: root)
        expect(first[:scanned]).to eq(50)
        expect(first[:processed]).to eq(49)
        expect(first[:failed]).to eq(1)
        expect(first[:next_cursor]).to eq(key_for(48))
        expect(first[:has_more]).to eq(true)

        allow(PaymentProof).to receive(:where)
          .with(storage_key: key_for(49))
          .and_call_original

        retry_result = described_class.call(cursor: first[:next_cursor], root: root)
        expect(retry_result[:scanned]).to eq(51)
        expect(retry_result[:orphaned]).to eq(51)
        expect(retry_result[:failed]).to eq(0)
      end

      it 'error pada entri ke-100 => next_cursor entri ke-99, retry entri ke-100' do
        100.times { |i| write_file(key_for(i), mtime: 2.days.ago) }

        allow(PaymentProof).to receive(:where)
          .with(storage_key: key_for(99))
          .and_raise(ActiveRecord::StatementInvalid.new('boom'))

        first = described_class.call(cursor: cursor, root: root)
        expect(first[:scanned]).to eq(100)
        expect(first[:processed]).to eq(99)
        expect(first[:failed]).to eq(1)
        expect(first[:next_cursor]).to eq(key_for(98))
        expect(first[:has_more]).to eq(true)

        allow(PaymentProof).to receive(:where)
          .with(storage_key: key_for(99))
          .and_call_original

        retry_result = described_class.call(cursor: first[:next_cursor], root: root)
        expect(retry_result[:scanned]).to eq(1)
        expect(retry_result[:orphaned]).to eq(1)
        expect(retry_result[:failed]).to eq(0)
      end

      it 'SQLite3::BusyException diklasifikasikan failed, bukan orphaned' do
        write_file(valid_key, mtime: 2.days.ago)

        allow(PaymentProof).to receive(:where)
          .with(storage_key: valid_key)
          .and_raise(SQLite3::BusyException, 'database is locked')

        result = described_class.call(cursor: cursor, root: root)

        expect(result[:failed]).to eq(1)
        expect(result[:orphaned]).to eq(0)
        expect(result[:has_more]).to eq(true)
      end
    end

    context 'error enumerasi direktori' do
      it 'mempertahankan cursor input dan has_more true' do
        allow(root).to receive(:entries).and_raise(Errno::EACCES)

        result = described_class.call(cursor: 'cursor-lama', root: root)

        expect(result[:scanned]).to eq(0)
        expect(result[:failed]).to eq(1)
        expect(result[:next_cursor]).to eq('cursor-lama')
        expect(result[:has_more]).to eq(true)
      end
    end
  end
end
