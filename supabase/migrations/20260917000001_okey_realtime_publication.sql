-- =============================================================================
-- 101 Okey — MASA TABLOLARI REALTIME YAYINA (publication) EKLENİYOR
-- -----------------------------------------------------------------------------
-- ŞİKAYET (kullanıcı, 2026-09-17): "iki-üç gerçek kullanıcı aynı masaya
-- girdik ama sanki aynı masada değilmişiz gibi oynuyorduk."
--
-- ## Kök neden: istemci abone oluyor, sunucu hiç YAYINLAMIYOR
--
-- Oyun ekranının tek senkron mekanizması realtime'dır: OkeyGameProvider
-- (lib/okey/providers/okey_game_provider.dart) masaya girerken DÖRT tabloya
-- postgres_changes aboneliği açar (bkz. OkeyRealtimeService.subscribe) —
-- okey_matches, okey_player_hands, okey_table_melds, okey_moves — ve gelen
-- her olayı "bir şey değişti, DB'den tazele" sinyali olarak kullanır.
-- Ekranın SANİYELİK zamanlayıcısı (_onTick) yalnızca sayaç rozetini besler,
-- DB'den okuma YAPMAZ; yani realtime susarsa masa tamamen donar.
--
-- Oysa bu dört tablonun HİÇBİRİ `supabase_realtime` publication'ında değildi
-- (canlıda doğrulandı: yayında Okey adına yalnızca okey_gifts_sent ve
-- okey_room_spectators vardı). Postgres bu tabloların değişikliklerini
-- mantıksal replikasyona hiç yazmadığı için Realtime'ın gönderecek bir şeyi
-- olmadı: abonelik "SUBSCRIBED" der, tek bir olay bile gelmez. Sessiz hata.
--
-- BOTLARLA FARK EDİLMEDİ: bota karşı oynarken masayı ilerleten zaten
-- oynayanın KENDİ istemcisidir (bot sırasını o tetikler, sonra tazeler).
-- Masada ikinci bir İNSAN olunca ortaya çıktı — herkes yalnızca kendi
-- hamlesini görüyor, diğerininkini asla.
--
-- KANIT (oda e5f4427a, 2026-09-17 17:41, iki insan + iki bot): insan
-- koltukları sırası geldiğini hiç öğrenemediği için tur tur
-- `timeout_auto_discard` ile ilerledi (17:42:13, 17:44:15, 17:45:42,
-- 17:46:44, 17:47:55, 17:48:34 …), bot koltukları ise her seferinde anında
-- oynadı. Yani masayı ilerleten şey oyuncular değil, 20260915000001'deki
-- pg_cron süpürücüsüydü.
--
-- ## Neden SADECE bu dört tablo
--
-- Yayına tablo eklemek bedava değil: her satır değişikliği WAL'dan akar ve
-- her abone için RLS'ten geçirilir. Bu yüzden yalnızca yayımlanmış
-- istemcinin GERÇEKTEN abone olduğu dört tablo eklenir.
--   * okey_rooms / okey_room_players EKLENMEZ — oda ekranının kendi 3
--     saniyelik yoklaması var (OkeyRoomProvider._pollTimer) ve
--     okey_room_players her 10 saniyede bir "buradayım" damgasıyla
--     (last_seen_at) güncelleniyor: yayına girseydi masadaki dört oyuncu
--     için sürekli, işe yaramaz bir olay seli üretirdi.
--
-- ## Güvenlik: yayın RLS'i atlatmaz
--
-- Realtime her olayı abonenin kendi yetkisiyle süzer; buradaki politikalar
-- zaten doğru ayrımı yapıyor:
--   * okey_player_hands → `user_id = auth.uid()` (SADECE kendi eli): masadaki
--     kimse rakibinin taşlarını realtime üzerinden GÖREMEZ.
--   * okey_matches / okey_table_melds / okey_moves → can_view_okey_room /
--     can_view_okey_match (masada oturanlar ve izleyiciler) — istemcinin
--     zaten SELECT ile okuduğu, masaya açık bilgi. Destenin kendisi
--     okey_matches'te DURMAZ (yalnızca deck_remaining sayısı), yani kapalı
--     deste sızmaz.
--
-- REPLICA IDENTITY'ye DOKUNULMAZ: dört tablonun da birincil anahtarı var
-- (varsayılan replica identity yeter), dolayısıyla UPDATE'ler
-- "cannot update table ... does not have a replica identity" hatasına
-- DÜŞMEZ. FULL'e çekmek eski satırı da yayına koyardı — gereksiz yük ve
-- gereksiz veri.
--
-- ## İSTEMCİ GÜNCELLEMESİ GEREKTİRMEZ
--
-- Google Play'deki 1.3.1+37 sürümü bu abonelikleri ZATEN açıyor; eksik olan
-- tek şey sunucunun yayınıydı. Bu göç uygulandığı anda sahadaki mevcut
-- sürüm senkron olmaya başlar.
-- =============================================================================

SET search_path = public, pg_temp;

DO $$
DECLARE
  v_table text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    RAISE NOTICE 'supabase_realtime publication yok — Okey realtime yayını atlandı';
    RETURN;
  END IF;

  FOREACH v_table IN ARRAY ARRAY[
    'okey_matches',      -- sıra, faz, gösterge, skor: masanın ana durumu
    'okey_player_hands', -- YALNIZCA kendi elim (RLS: user_id = auth.uid())
    'okey_table_melds',  -- açılan/işlenen perler
    'okey_moves'         -- hamle akışı (çek/at) — animasyon ve ses tetiği
  ]
  LOOP
    IF EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = v_table
    ) THEN
      CONTINUE;
    END IF;

    EXECUTE format(
      'ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_table
    );
    RAISE NOTICE 'supabase_realtime publication''ına eklendi: %', v_table;
  END LOOP;
END;
$$;
