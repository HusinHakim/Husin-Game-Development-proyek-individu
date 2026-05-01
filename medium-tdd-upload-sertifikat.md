# TDD di Proyek Nyata: Bukan Teori, Tapi Pengalaman

*Catatan dari mengerjakan fitur Upload Sertifikat dengan disiplin RED-GREEN-REFACTOR*

---

![IMAGE: Hero image — developer melihat layar dengan terminal test hijau]

---

Jujur, saya sempat merasa TDD itu buang-buang waktu. Kenapa harus nulis test dulu kalau fiturnya aja belum ada?

Pikiran itu berubah waktu saya mulai ngerjain **PBI-17: Upload Sertifikat** di proyek *Guru Besar Mengajar*. Ini bukan fitur yang rumit di permukaan: Admin upload PDF, disimpan ke Supabase, Kaprodi/Guru Besar bisa unduh. Tapi aturan bisnisnya banyak, dan di situlah TDD mulai terasa manfaatnya.

---

## Momen Pertama yang Bikin Saya "Ngeh"

Waktu mulai nulis test untuk validasi file PDF, saya iseng cek validator yang sudah ada di `documents/`. Ternyata validator itu cuma ngecek MIME type dari header request. Gampang banget dipalsukan: upload file shell script, kasih nama `.pdf`, set content-type ke `application/pdf`, lolos.

Kalau saya langsung koding implementasinya tanpa nulis test dulu, bug itu mungkin baru ketahuan pas review atau bahkan pas production. Karena saya harus nulis test dulu, saya *terpaksa* mikirin: "Apa saja yang bisa bikin validasi ini jebol?"

Jawabannya: magic bytes. Saya tambahkan pengecekan `%PDF-` di byte pertama file. Test tertulis, implementasi ngikut.

---

## Ritme RED-GREEN yang Awalnya Terasa Aneh

Pola commit saya di fitur ini terlihat seperti ini:

```
[RED]   test: add SertifikatService upload success and kegiatan status tests (+, -)
[GREEN] feat: add SertifikatService.upload_sertifikat core logic

[RED]   test: add SertifikatService participant membership validation tests (-, corner)
[GREEN] feat: add participant validation in SertifikatService

[RED]   test: add SertifikatService re-upload idempotency tests (corner)
[GREEN] feat: add update_or_create re-upload support in SertifikatService
```

![IMAGE: Screenshot git log --oneline menampilkan pola RED/GREEN bergantian]

Awalnya ini terasa ritual yang dipaksakan. Tapi setelah beberapa siklus, saya sadar: commit ini adalah bukti nyata urutan kerja saya. Siapapun yang buka git log bisa verifikasi bahwa test ditulis sebelum kode, bukan sebaliknya.

---

## Tiga Jenis Test yang Mengubah Cara Saya Berpikir

Yang paling berdampak dari pengerjaan ini adalah disiplin menulis tiga jenis test untuk setiap fitur.

![IMAGE: Ilustrasi tiga kategori test: positive, negative, corner case]

**Positive** itu mudah. Semua input valid, hasilnya sesuai harapan. Ini yang biasanya saya tulis dulu.

**Negative** mulai memaksa saya mikir lebih keras:

```python
def test_upload_rejected_when_kegiatan_not_selesai(self):
    self.kegiatan.status = 'BERLANGSUNG'
    self.kegiatan.save()
    response = self.client.post('/api/sertifikat/upload/', {...})
    self.assertEqual(response.status_code, 409)

def test_upload_rejected_for_non_participant(self):
    response = self.client.post('/api/sertifikat/upload/', {
        'user_id': str(self.other_user.id),  # bukan peserta
        ...
    })
    self.assertEqual(response.status_code, 403)
```

**Corner case** adalah yang paling seru. Di sinilah saya perlu diskusi dengan tim:

```python
def test_file_exactly_5mb_is_accepted(self):
    five_mb = b'%PDF-' + b'A' * (5 * 1024 * 1024 - 5)
    file = SimpleUploadedFile("cert.pdf", five_mb, content_type="application/pdf")
    response = self.client.post('/api/sertifikat/upload/', {'content': file, ...})
    self.assertEqual(response.status_code, 201)  # tepat 5MB harus diterima

def test_reupload_overwrites_existing_certificate(self):
    SertifikatModel.objects.create(user=self.guru_besar, kegiatan=self.kegiatan,
                                    content="https://old-url.com")
    response = self.client.post('/api/sertifikat/upload/', {...})
    self.assertEqual(response.status_code, 201)
    self.assertEqual(
        SertifikatModel.objects.filter(user=self.guru_besar, kegiatan=self.kegiatan).count(), 1
    )
```

Corner case re-upload itu muncul dari pertanyaan sederhana: kalau Admin salah upload sertifikat, apa yang terjadi? Harus error? Atau overwrite? Keputusan bisnis itu harus tertulis sebagai test, bukan asumsi tersembunyi di dalam kode.

---

## Mock itu Bukan Cheat, Tapi Desain

Proyek ini pakai Supabase sebagai storage. Saya tidak mau test jalan lama karena harus koneksi ke Supabase sungguhan, dan tidak mau bucket penuh file test sampah.

Solusinya: mock di layer yang tepat.

```python
# Layer service: mock Supabase client
@patch("sertifikat.services.DocumentSupabaseClient.upload_sertifikat")
def test_upload_success_saves_url_to_model(self, mock_upload):
    mock_upload.return_value = "https://storage.example.com/cert.pdf"
    result = SertifikatService.upload_sertifikat(...)
    self.assertEqual(result.content, "https://storage.example.com/cert.pdf")
    mock_upload.assert_called_once()
```

```python
# Layer view: mock seluruh service
@patch("sertifikat.views.views_admin.SertifikatService.upload_sertifikat")
def test_admin_upload_returns_201(self, mock_service):
    mock_service.return_value = self.mock_sertifikat_instance
    self.client.force_authenticate(user=self.admin)
    response = self.client.post('/api/sertifikat/upload/', self.valid_payload, format='multipart')
    self.assertEqual(response.status_code, 201)
```

Karena saya harus memutuskan *apa yang perlu di-mock*, saya jadi memahami dengan jelas di mana batas tanggung jawab setiap layer. Test view hanya mengecek: apakah request diteruskan ke service dengan benar? Business logic bukan urusan test view.

![IMAGE: Diagram layer View, Service, Serializer, Supabase Client dengan keterangan posisi mock]

---

## Coverage dan Mutation Testing: Angka yang Bermakna

Setelah semua test hijau, saya jalankan coverage report:

```bash
pytest --cov=sertifikat --cov-report=term-missing
```

```
Name                          Stmts   Miss  Cover
-------------------------------------------------
sertifikat/models.py             18      0   100%
sertifikat/services.py           52      0   100%
sertifikat/views/views_admin.py  28      1    96%
TOTAL                           151      3    98%
```

![IMAGE: Screenshot HTML report dari pytest-cov]

Tapi 98% coverage tidak selalu berarti test-nya bagus. Masuk `mutmut`:

```bash
mutmut run --paths-to-mutate sertifikat/services.py
```

Mutmut mengubah kode saya secara otomatis (misalnya `>` jadi `>=`, `or` jadi `and`) lalu jalankan test. Kalau test tetap hijau setelah mutasi, artinya test saya tidak benar-benar mendeteksi perubahan itu.

```
Mutation score: 94.3% (66/70 mutants killed)

Survived:
- services.py:47 — changed `>` to `>=` (file size check)
```

Dari sini saya tahu: test ukuran file saya tidak cukup ketat karena tidak ada test yang bedain "tepat 5MB diterima" dan "5MB + 1 byte ditolak". Itu yang mendorong saya nulis corner case spesifik itu.

![IMAGE: Screenshot output mutmut dengan killed vs survived mutants]

---

## Yang Masih Susah

Satu hal yang saya belum sepenuhnya nyaman: setup fixture dan mock di awal memakan waktu lebih lama dari nulis implementasinya sendiri. Ada momen di mana saya habiskan 30 menit cuma untuk setup `setUp()` yang benar sebelum bisa nulis satu test.

Tapi saya mulai lihat pola: makin kompleks setup-nya, biasanya makin kompleks juga dependensi di kode saya. Itu sinyal untuk refactor, bukan alasan untuk skip test.

---

## Takeaway

TDD di proyek nyata bukan tentang disiplin yang kaku. Ini tentang punya percakapan dengan diri sendiri sebelum nulis kode: *"Apa yang akan terjadi kalau kondisi ini tidak terpenuhi?"*

Kalau satu fitur punya 30+ test dengan positive, negative, dan corner case yang lengkap, itu bukan beban. Itu aset. Developer berikutnya yang menyentuh kode ini punya safety net, dan saya punya confidence untuk refactor tanpa takut ada yang rusak tanpa ketahuan.

---

![IMAGE: Terminal dengan semua test passed dan coverage report]

---

*Ditulis sebagai bagian dari dokumentasi PBI-17 Upload Sertifikat dalam proyek Guru Besar Mengajar.*

**Tags:** `#TDD` `#Django` `#Python` `#Testing` `#SoftwareEngineering`
