-- =============================================================================
-- 20260922000001_bot_showcase_accounts_batch2.sql
-- -----------------------------------------------------------------------------
-- 50 yeni vitrin/bot hesabı (25 kadın + 25 erkek), mevcut "Kız & Erkek" hazır
-- karakter avatarlarını kullanır (bkz. lib/features/profile/models/
-- character_avatar_recipes.dart). Kullanıcı isteği: bio YOK, botlar mesaj
-- ATABİLSİN ama kendilerine mesaj başlatılamasın.
--
-- Mevcut bot sağlama altyapısı (private.provision_bot_auth_user, bkz.
-- 20260908130004_bot_auth_provisioning.sql) aynen yeniden kullanılıyor:
--   * auth.users satırı banned_until=+100 yıl ile açılır (giriş yapamaz),
--   * messages_enabled=false VE allow_messages_from_non_followers=false o
--     fonksiyonda zaten sabit — yani BAŞKALARI bu botlara mesaj başlatamaz.
--   * Botun KENDİSİ mesaj göndermesi bu ayarla kısıtlanmaz: chat_service.dart
--     içindeki getOrCreateConversation yalnızca ALICININ (karşı tarafın)
--     messages_enabled değerine bakar (bkz. lib/features/chat/services/
--     chat_service.dart) — gönderen tarafın kendi ayarı kontrol edilmiyor.
--     (Botlar auth.users'ta banned_until ile gerçek oturum açamadığından,
--     istemciden mesaj göndermeleri zaten ayrı bir bot-mesaj kuyruğu/RPC
--     gerektirir; bu migration yalnız hesapları ve izin ayarlarını kurar.)
--   * is_bot=true → admin üye sayaçlarına dahil olmaz (20260908130001).
--
-- Avatarlar bu migration'dan ÖNCE storage'a yüklendi:
--   npx supabase storage cp --linked --experimental -r "_bot_avatars_batch2" "ss:///avatars"
-- → public URL: https://xsbukxkgtmdyickknqzf.supabase.co/storage/v1/object/public/avatars/_bot_avatars_batch2/<dosya>
--
-- İdempotent: kullanıcı adı veya e-postası zaten varsa o satır atlanır.
-- =============================================================================

begin;

DO $$
DECLARE
  v_row record;
  v_id uuid;
  v_email text;
  v_avatar_url text;
  v_created integer := 0;
BEGIN
  FOR v_row IN
    SELECT * FROM (VALUES
      ('nazli.erkan', 'Nazlı Erkan', 'avatar_char_13.png'),
      ('esrabulut', 'Esra Bulut', 'avatar_char_15.png'),
      ('newroz.aygun', 'Newroz Aygün', 'avatar_char_17.png'),
      ('sevdaekinci', 'Sevda Ekinci', 'avatar_char_19.png'),
      ('beritan.kurt', 'Beritan Kurt', 'avatar_char_21.png'),
      ('sudesari', 'Sude Sarı', 'avatar_char_23.png'),
      ('seyma.yavuz', 'Şeyma Yavuz', 'avatar_char_37.png'),
      ('kaderozdemir', 'Kader Özdemir', 'avatar_char_39.png'),
      ('azime.kocabas', 'Azime Kocabaş', 'avatar_char_41.png'),
      ('cerenyildiz', 'Ceren Yıldız', 'avatar_char_43.png'),
      ('dilan.gunes', 'Dilan Güneş', 'avatar_char_45.png'),
      ('havinbaysal', 'Havin Baysal', 'avatar_char_47.png'),
      ('cemile.cicek', 'Cemile Çiçek', 'avatar_char_49.png'),
      ('evinkoc', 'Evin Koç', 'avatar_char_77.png'),
      ('hazal.bozkurt', 'Hazal Bozkurt', 'avatar_char_79.png'),
      ('buseozkan', 'Buse Özkan', 'avatar_char_81.png'),
      ('silan.tekin', 'Şilan Tekin', 'avatar_char_83.png'),
      ('elifturan', 'Elif Turan', 'avatar_char_85.png'),
      ('songul.unal', 'Songül Ünal', 'avatar_char_87.png'),
      ('yaseminsolmaz', 'Yasemin Solmaz', 'avatar_char_89.png'),
      ('meryem.kaplan', 'Meryem Kaplan', 'avatar_char_91.png'),
      ('sultanyalcin', 'Sultan Yalçın', 'avatar_char_93.png'),
      ('zeynep.aksoy', 'Zeynep Aksoy', 'avatar_char_95.png'),
      ('tugbakutlu', 'Tuğba Kutlu', 'avatar_char_97.png'),
      ('aylin.dogru', 'Aylin Doğru', 'avatar_char_99.png'),
      ('rojhat.sari', 'Rojhat Sarı', 'avatar_char_01.png'),
      ('fikretbaysal', 'Fikret Baysal', 'avatar_char_03.png'),
      ('hasan.yavuz', 'Hasan Yavuz', 'avatar_char_05.png'),
      ('mustafaturan', 'Mustafa Turan', 'avatar_char_07.png'),
      ('sinan.gunes', 'Sinan Güneş', 'avatar_char_09.png'),
      ('kenanozdemir', 'Kenan Özdemir', 'avatar_char_11.png'),
      ('ekrem.kutlu', 'Ekrem Kutlu', 'avatar_char_25.png'),
      ('kaanerkan', 'Kaan Erkan', 'avatar_char_27.png'),
      ('volkan.ozkan', 'Volkan Özkan', 'avatar_char_29.png'),
      ('bedrankocabas', 'Bedran Kocabaş', 'avatar_char_31.png'),
      ('huseyin.yildiz', 'Hüseyin Yıldız', 'avatar_char_33.png'),
      ('tarikaksoy', 'Tarık Aksoy', 'avatar_char_35.png'),
      ('devrim.koc', 'Devrim Koç', 'avatar_char_50.png'),
      ('muratbulut', 'Murat Bulut', 'avatar_char_52.png'),
      ('diyar.karadag', 'Diyar Karadağ', 'avatar_char_54.png'),
      ('ibrahimaygun', 'İbrahim Aygün', 'avatar_char_56.png'),
      ('ugur.dogru', 'Uğur Doğru', 'avatar_char_58.png'),
      ('yasincicek', 'Yasin Çiçek', 'avatar_char_60.png'),
      ('emre.aydogan', 'Emre Aydoğan', 'avatar_char_62.png'),
      ('alitekin', 'Ali Tekin', 'avatar_char_64.png'),
      ('levent.aydemir', 'Levent Aydemir', 'avatar_char_66.png'),
      ('ahmetguler', 'Ahmet Güler', 'avatar_char_68.png'),
      ('gokhan.toprak', 'Gökhan Toprak', 'avatar_char_70.png'),
      ('zanayalcin', 'Zana Yalçın', 'avatar_char_72.png'),
      ('welat.kaplan', 'Welat Kaplan', 'avatar_char_74.png')
    ) AS t(username, full_name, avatar_file)
  LOOP
    IF EXISTS (SELECT 1 FROM public.profiles WHERE lower(username) = v_row.username) THEN
      CONTINUE;
    END IF;

    v_email := v_row.username || '@bot.cizreapp.local';
    IF EXISTS (SELECT 1 FROM auth.users WHERE email = v_email) THEN
      CONTINUE;
    END IF;

    v_id := gen_random_uuid();
    v_avatar_url := 'https://xsbukxkgtmdyickknqzf.supabase.co/storage/v1/object/public/avatars/_bot_avatars_batch2/'
                     || v_row.avatar_file;

    PERFORM private.provision_bot_auth_user(
      v_id, v_email, v_row.full_name, v_row.username,
      NULL, NULL, v_avatar_url, NULL,
      -- Kayıt tarihlerini geçmişe yay: hepsi aynı anda açılmış görünmesin.
      now() - make_interval(days => 20 + floor(random() * 300)::integer),
      now() - make_interval(hours => floor(random() * 72)::integer)
    );

    INSERT INTO public.bot_accounts (id, persona)
    VALUES (v_id, NULL)
    ON CONFLICT (id) DO NOTHING;

    v_created := v_created + 1;
  END LOOP;

  RAISE NOTICE 'bot_showcase_accounts_batch2: % bot oluşturuldu', v_created;
END;
$$;

commit;
