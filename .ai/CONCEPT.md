# Midnight Geprek — Konsep Ringkas

Game horror bertema aktivitas (job simulation) di Roblox.
Player menjadi penjual ayam geprek yang melayani pembeli. Tidak semua pembeli
manusia normal: sebagian adalah anomali. Melayani anomali berujung punishment,
termasuk jumpscare.

## Loop inti
Pelanggan datang → observasi → cek pesanan/perilaku → masak → layani ATAU tolak
→ uang/reputasi berubah → investigasi/quest → akhir hari → hari berikutnya → ending.

## Aturan punishment anomali (klarifikasi terhadap PROJECT_INSTRUCTIONS §2.3)
Jumpscare hanya sebagai punishment anomali; ini menggantikan larangan umum jumpscare
di §2.3. Aturan:

- Jumpscare dipicu SERVER saat anomali dilayani; client hanya memutar efek.
- Tanpa gore, gaya stylized, singkat (TUNABLE: ~1–2 detik).
- Intensitas configurable: Off / Reduced / Full. Reduced/Off = tanpa flash dan tanpa suara keras.
- Tanpa strobo (hindari >3 flash per detik).
- Ada cooldown agar jumpscare tidak beruntun.
- Punishment berjenjang (TUNABLE): kesalahan pertama ringan, pengulangan makin berat.
- Setiap anomali wajib punya clue visual, bukan hanya audio.
- Punishment mengubah uang/reputasi lewat EconomyService/ReputationService; reputasi 0 tetap memicu Bangkrut via EndingService.
