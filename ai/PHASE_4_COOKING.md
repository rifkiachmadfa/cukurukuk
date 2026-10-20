# Phase 4 — Cooking & Serving (catatan implementasi)

Status: **Ready for Review** (belum diuji di Roblox Studio). Mencakup 4.1 (config stasiun/resep), 4.2 (lifecycle memasak), 4.3 (serve handoff). 4.4 (kualitas & hukuman kesalahan) **belum dikerjakan** — saat ini kesalahan hanya berarti ulang dari awal.

## Alur pemain

1. **FoodBox** (prompt) → `ServerStorage.FoodBox` di-clone ke `TrayPlacement`.
2. **Chicken** (prompt) → `ServerStorage.Models.Chicken` di-clone ke model `Geprek`.
3. **Geprek** (prompt) → ayam digeprek (skala `SmashScale`, atribut `Smashed`).
4. **Sambal** (`Stasion.Sambal.Hijau/Korek/Matah/Original`) → ayam dimasukkan ke FoodBox di `TrayPlacement`.
5. Ulangi 1–4 sampai jumlah porsi di nampan = jumlah porsi order (maks 3).
6. **Tray** (prompt) → server cocokkan sambal nampan dengan order.
   - Cocok: `Cooking → Ready → Served`.
   - Tidak cocok: nampan dibersihkan, pemain ulang dari awal. Order tetap `Cooking`, timer 2 menit jalan terus.

## Kontrak map (nama di `CookingConfig`)

| Objek | Lokasi |
|---|---|
| FoodBox part + ProximityPrompt | Workspace |
| Chicken part + ProximityPrompt | Workspace |
| Geprek model + ProximityPrompt | Workspace |
| Hijau, Korek, Matah, Original + ProximityPrompt | Workspace.Stasion.Sambal |
| TrayPlacement (BasePart) | Workspace |
| Tray (ProximityPrompt, atau part berisi prompt) | Workspace |
| FoodBox (Model) | ServerStorage |
| Chicken (Model) | ServerStorage.Models |

Ganti nama di map = ubah `CookingConfig.luau` saja. Jika ada objek yang tidak ditemukan dalam `ResolveTimeoutSeconds`, Output menampilkan `[CookingService] CookingService TIDAK aktif. Objek belum ditemukan: ...`.

## Keputusan / ASSUMPTION

- Sambal order diganti ke 4 id stasiun: `hijau`, `korek`, `matah`, `original` (sebelumnya tidak_pedas/sedang/pedas/extra_pedas). `extraPrice` dan `weight` adalah angka sementara (TUNABLE CONFIG).
- `Ready` hanya sesaat: dicapai dan langsung `Served` di satu aksi Tray. Prompt "Antar" di layar order praktis tidak muncul.
- Order di-bind ke sesi saat FoodBox pertama ditekan: order `Accepted` tertua. Asumsi satu juru masak (MVP single-player).
- Hint tampil lewat BillboardGui di `TrayPlacement` (tanpa client script). UI client resmi menyusul di Phase 11.3.
- `Debug.DevAutoCook = false`: dev harness tidak lagi memalsukan Cooking/Ready.
- Belum ada uang/reputasi; Phase 5 mendengarkan `OrderService.OrderChanged` (`Served`).
