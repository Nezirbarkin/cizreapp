# Görev Yaparak Kazan — Kullanım ve Deployment Rehberi

> Eklenme tarihi: 2026-07-19
> İlgili SQL migration'ları: `20260719000001_task_earning_system.sql`, `20260719000002_task_earning_rls_rpc.sql`, `20260719000003_fix_get_active_tasks_signature.sql`

## 1. Genel Bakış

Kullanıcılar, admin tarafından yayınlanan görevlere (Instagram takip, video izleme, uygulama indirme vb.) katılarak ekran görüntüsü yükler. Admin onayından sonra bakiyelerine ödül eklenir.

### Akış Diyagramı

```
[Yayın: Admin → Görev oluştur]
        ↓
[Kullanıcı → Görev listesi (GetActiveTasks)]
        ↓
[Kullanıcı → CLAIM (claim_task RPC, FOR UPDATE lock)]
        ↓
[Kullanıcı → Ekran görüntüsü yükle (task_screenshots bucket)]
        ↓
[Kullanıcı → submit_task_with_proof RPC]
        ↓
[Admin → Bekleyenler sekmesi (admin_get_task_submissions)]
        ↓
[Admin → ONAY (approve_task_submission) | RED (reject_task_submission)]
        ↓
[add_to_balance(task_reward) → atomik bakiye ekleme]
        ↓
[notifications → task_approved/task_rejected]
```

## 2. SQL Migration Sırası

Supabase Dashboard'da SQL Editör'ü açın ve sırayla çalıştırın:

1. `supabase/20260719000001_task_earning_system.sql`
   - Tablolar: `task_categories`, `tasks`, `task_submissions`
   - Enum'lar: `task_status`, `task_submission_status` + `balance_transaction_type.task_reward`
   - Storage bucket: `task_screenshots`
   - 8 başlangıç kategorisi (idempotent INSERT)

2. `supabase/20260719000002_task_earning_rls_rls_rpc.sql`
   - 7 RPC: `claim_task`, `submit_task_with_proof`, `approve_task_submission`, `reject_task_submission`, `admin_get_task_submissions`, `get_active_tasks`, `get_user_task_history`, `get_task_stats`
   - RLS politikaları (her 3 tablo + storage.objects)
   - Realtime publication'a `task_submissions` ve `tasks` eklenir

3. `supabase/20260719000003_fix_get_active_tasks_signature.sql`
   - `get_active_tasks` için DROP+CREATE (signature `id` → `task_id`, qualified subqueries, `created_at` eklendi)

## 3. Admin Tarafı

- Drawer > "Görev Yönetimi" menüsü
- **Görevler** sekmesi: liste, oluşturma formu (FAB), durum dropdown, silme
- **Başvurular** sekmesi: bekleyen/onaylı/red sekmeli filtre, ekran görüntüsü önizleme, onay/red butonları, realtime güncelleme
- **İstatistikler** sekmesi: görev/başvuru sayıları, bugünkü/toplam ödeme kartı

## 4. Kullanıcı Tarafı

- Cüzdan ekranında "İzleyerek Kazan" kartının altında mor "Görev Yaparak Kazan" kartı
- Görev listesi (kategori filtresi, sınıf kartları)
- Görev detay: claim butonu → ekran görüntüsü yükleme → not ekleme → gönder
- AppBar'da bekleyen başvuru sayısı (badge)
- Geçmiş ekranı: status filtreli, ekran görüntüsü küçük resim, red gerekçesi gösterimi

## 5. Güvenlik Notları (PROJE_HAVIZA referansları)

| ID | Konu |
|----|------|
| §4.1.7 | Bakiye mutasyonu yalnız service_role policy + RPC SECURITY DEFINER |
| §4.1.1 | Admin kontrolü profiles subquery (helper fn zinciri recursion önlemi) |
| §4.1.5 | Trigger/RPC'lerde `auth.uid()` kullanılmadı — yalnız `NEW.user_id` parametre |
| §4.1.6 | Race condition: partial unique index `(task_id, user_id) WHERE status IN ('pending','approved')` |
| §4.1.4 | `tasks.current_participants` denormalize counter — race condition koruması için FOR UPDATE lock |
| YENİ | Idempotency: approve_task_submission status='approved' guard → çift ödeme engelleme |
| YENİ | RLS admin policy'leri `EXISTS(SELECT 1 FROM profiles WHERE id=auth.uid() AND role='admin')` pattern'i kullanır |
| YENİ | Linter güvenliği: `REVOKE ALL ON FUNCTION ... FROM PUBLIC` + `TO authenticated, service_role` |

## 6. Edge-case Davranışları

| Senaryo | Beklenen |
|---------|----------|
| Aynı kullanıcı aynı göreve 2 kez claim | RPC EXCEPTION 'zaten katıldınız' + DB partial unique index → çift INSERT rollback |
| `current_participants == max_participants` iken claim | RPC EXCEPTION 'limit dolmuş' + status otomatik 'completed' |
| Admin ikinci kez approve | RPC `status='already_approved'` (idempotent) + bakiye tekrar eklenmez |
| Admin red → status='completed' ise | `current_participants--` + status tekrar 'active' (limit geri açılır) |
| Pending başvuru için 2 ekran görüntüsü | UPDATE WHERE status='pending' — yeni görsel değiştirir |
| Storage yükleme hatası | Frontend catch + kullanıcıya SnackBar |
| RPC deploy edilmeden client çağrısı | PostgrestException → SnackBar hata mesajı |

## 7. Test Senaryoları (Manuel)

1. Admin > Görev Yönetimi > Yeni Görev: ₺5 ödül + 100 katılımcı limiti + aktif
2. Kullanıcı > Cüzdan > Görev Yaparak Kazan → listede gör
3. Kullanıcı → Görev detay → "Göreve Katıl"
4. Kullanıcı → Ekran görüntüsü yükle → Not ekle → Gönder
5. Admin > Başvurular > Bekleyen → Ekran görüntüsü gör → Onayla
6. Kullanıcı > Cüzdan > bakiye +₺5
7. Kullanıcı > İşlem Geçmişi > "Görev Ödülü" kaydı görünsün (yeşil +)
8. Kullanıcı > Görev Geçmişim > "Onaylandı ✓" badge

## 8. Geliştirici Notları

- Realtime admin tarafında otomatik çalışır (subscribeAllSubmissions)
- Kullanıcı tarafı manuel yenileme gerekir (`getUserPendingCount` AppBar badge'i için)
- `_pickImage` `image_picker` ^1.0.0 (proje zaten dahil)
- `signed_in_user_id`/`auth.uid()` ayrımına dikkat — RPC SECURITY DEFINER postgres'a düşer, ama RLS hâlâ aktif
- Migration 3 (signature fix) idempotent değildir — DROP+CREATE yapar; tekrar çalıştırılabilir ama bildirim trigger'ları etkilenmez

## 9. Bilinen Sınırlamalar

- Realtime sadece admin panelde dinlenir; kullanıcı tarafında manuel yenileme gerekir (tasarruf)
- Bildirim push (FCM) trigger'a bağlı değildir; sadece `notifications` tablosuna yazılır. Mevcut FCM trigger'ı ayrı bir mekanizma
- Storage cache-bust: dosya adına timestamp eklenir ama `cache-control` header'ı eklenmedi → agresif cache'de eski görsel görünebilir
- Maksimum 1 ekran görüntüsü (ileride çoklu ekran görüntüsü eklenirse `task_submission_screenshots` alt tablosu)
