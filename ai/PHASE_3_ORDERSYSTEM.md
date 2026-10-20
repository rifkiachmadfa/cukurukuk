# Phase 3 — OrderSystem (catatan implementasi)

> Catatan ini diperbarui oleh setiap patch Phase 3. Status hanya berubah menjadi **Verified by User** setelah pemilik proyek menjalankannya di Studio.
> Semua path di bawah adalah **ASSUMPTION** mengikuti baseline `src/ReplicatedStorage/Shared` dan `src/ServerScriptService/Services` di PROJECT_INSTRUCTIONS. Sesuaikan jika `default.project.json` berbeda.

## Status sub-phase

| Sub-phase | Isi | Status |
|---|---|---|
| 3.1 | Order data model, lifecycle, OrderService | Ready for Review |
| 3.2 | Remotes + validasi intent (Accept/Refuse/Serve) | Ready for Review |
| 3.3 | Integrasi CustomerService (Customer AI belum ada; API `CreateOrder` siap dipakai) | Not Started |
| 3.4 | Tampilan order di part `screen` + ProximityPrompt (UI client sendiri belum dibuat) | Ready for Review |
| 3.5 | Serve/Refuse: transisi status server-side selesai; konsekuensi uang/reputasi menunggu Phase 5 | Partial - Ready for Review |
| 3.6 | Timeout pengerjaan 2 menit, closing/cleanup hooks | Ready for Review |
| 3.7 | Self-test OrderService + checklist manual | Ready for Review |

## Aturan pemilik proyek (di `OrderConfig`)

- `MaxGeprekPerOrder = 3` — total porsi geprek dalam SATU order tidak boleh lebih dari 3 (divalidasi server di `OrderService.ValidateLines`).
- `WorkTimeLimitSeconds = 120` — maksimal pengerjaan 2 menit, dihitung dari `Accepted` sampai `Served`.
- Layar menampilkan: jumlah porsi, pilihan sambal, harga per baris, total, status, countdown.

## ASSUMPTION / TUNABLE CONFIG

Belum ditentukan GDD, perlu playtest: `PresentedTimeoutSeconds` (60 dtk), harga geprek (Rp15.000), `extraPrice` tiap level sambal, bobot sambal/porsi, `MaxInteractDistance` (14 stud), `ActionCooldownSeconds`. Dengan Rp15.000/porsi, target Rp5.000.000 butuh sekitar 48 porsi/hari. Angka ini belum divalidasi (Phase 5.5 / 15.4).

## Lifecycle order

```
Created   -> Presented | Cancelled | Expired
Presented -> Accepted | Refused | Cancelled | Expired
Accepted  -> Cooking | Cancelled | Expired
Cooking   -> Ready | Cancelled | Expired
Ready     -> Served | Cancelled | Expired
Served / Refused / Cancelled / Expired = terminal (tidak bisa diubah lagi)
```

| Transisi | Dipicu oleh |
|---|---|
| Created -> Presented | `OrderService.CreateOrder` (otomatis) |
| Accepted / Refused / Served | Intent pemain, divalidasi `OrderActionHandler` |
| Cooking / Ready | CookingService (Phase 4, belum ada). Dev harness mensimulasikannya di Studio |
| Cancelled | `CancelOrder` / `CancelAll*` (customer pergi, toko tutup) |
| Expired | `OrderTimeoutService` saat deadline lewat |

Deadline: `Presented` memakai `PresentedTimeoutSeconds`; `Accepted` memakai `WorkTimeLimitSeconds` dan tetap berlaku sampai `Served`. Transisi yang datang setelah deadline tetapi sebelum timer berjalan tetap ditolak (`OrderExpired`), jadi tidak ada reward untuk order kedaluwarsa.

## Remote contract

Folder `ReplicatedStorage.OrderRemotes` (nama di `OrderConfig.Remotes`):

| Remote | Arah | Argumen | Hasil |
|---|---|---|---|
| `RequestOrderAction` (RemoteFunction) | client -> server | `action` ("Accept" / "Refuse" / "Serve"), `orderId` | `{ ok, code }` |
| `RequestOrderSnapshot` (RemoteFunction) | client -> server | — | daftar `OrderSummary` aktif |
| `OrderUpdated` (RemoteEvent) | server -> client | `OrderSummary` | — |

Client tidak pernah mengirim harga, reward, kategori customer, status, atau hasil keputusan. `OrderSummary` tidak berisi kategori customer atau metadata anomaly.

Kode hasil: `Ok`, `InvalidAction`, `InvalidOrderId`, `Cooldown`, `NotAllowed`, `NotFound`, `WrongStatus`, `NoCharacter`, `NoInteractionPoint`, `TooFar`, `IllegalTransition`, `OrderExpired`, `InternalError`.

## Titik integrasi berikutnya

- CustomerService: `OrderService:CreateOrder({ customerId, customerCategory })`; saat customer pergi panggil `Timeouts.OnCustomerLeft(customerId)`.
- DayCycleService: `Timeouts.OnShopClosing()` saat Closing/ganti hari; `ActionHandler:SetActionGate(fn)` untuk membatasi aksi per fase.
- CookingService: `OrderService:Transition(orderId, "Cooking" | "Ready")`.
- Economy/Reputation: dengarkan `OrderService.OrderChanged` dan filter `Served` / `Refused`. Harga ada di `OrderService:GetSummary(orderId).totalPrice` (dihitung server).
- Handler jarak (`SetInteractionPointProvider`) saat ini memakai posisi part `screen`; ganti ke posisi customer/counter saat Customer AI ada.

## Cara menguji

1. `rojo build -o build.rbxlx` lalu buka di Studio (atau `rojo serve` + Connect).
2. Pastikan ada Part bernama `screen` di Workspace, sisi depan menghadap pemain (atau ubah `Screen.Face`).
3. Tekan Play. Output harus menampilkan `[OrderSelfTest] done: N passed, 0 failed`.
4. Dev harness membuat order otomatis (hanya di Studio). Dekati layar, tekan **E** (Terima) atau **F** (Tolak).

### Checklist manual

- [ ] Layar menampilkan jumlah porsi, sambal, harga per baris, total, status, countdown.
- [ ] Order tidak pernah berisi lebih dari 3 porsi geprek.
- [ ] Terima: status berubah, countdown mulai dari 2:00; setelah beberapa detik status Siap diantar dan prompt Antar muncul.
- [ ] Antar: status Selesai, layar kembali kosong setelah beberapa detik, order berikutnya muncul.
- [ ] Biarkan 2 menit habis setelah Terima: status Waktu habis, Antar tidak bisa dipakai.
- [ ] Tolak: status Ditolak, tidak ada order menggantung.
- [ ] Tekan E dua kali cepat: hanya satu transisi (cooldown/status guard).
- [ ] Dari jarak jauh prompt tidak muncul. Uji juga memanggil `RequestOrderAction` dari command bar client dengan jarak jauh: harus `TooFar`.
- [ ] `RequestOrderAction:InvokeServer("Serve", "orderId-palsu")` mengembalikan `NotFound`/`InvalidOrderId` tanpa error di server.
- [ ] Hentikan Play: tidak ada error / koneksi menggantung di Output.

### Belum bisa diuji otomatis

Jarak dan spam remote butuh sesi Player nyata; UI SurfaceGui dan ProximityPrompt harus dicek visual (layar kecil/mobile). Patch ini belum dijalankan di Roblox Studio oleh penulisnya.
