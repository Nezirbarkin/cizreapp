# Paket Gönderme (Kurye) Özelliği - Manuel Test Planı

Bu bir otomatik `flutter test` değil; özellik çok yeni ve Supabase'e bağlı olduğu için
elle adım adım test edip hangi adımda hata çıktığını not almak en hızlı yol. Her adımda
"Beklenen" ile karşılaştır, uymuyorsa adım numarasıyla bana bildir.

## 0) Ön koşul
- [ ] Tüm migration'lar (courier_package_pricing, courier_extras, courier_balance_type,
      courier_settings_admin_update, add_package_notification_types) SQL Editor'de çalıştırılmış mı?
- [ ] `send-order-email` edge function deploy edilmiş mi?
- [ ] Test kullanıcısının bakiyesi en az 50₺ (deneme ücretini karşılayacak) mi?
- [ ] En az 1 kullanıcının `profiles.role = 'courier'` olduğundan emin ol.

## 1) Admin — Ayarlar (Kurye Yönetimi → Ayarlar)
1. Komisyon %, Açılış Ücreti, Km Ücreti değerlerini değiştir, Kaydet.
   - Beklenen: yeşil "Ayarlar kaydedildi" mesajı. Sayfadan çıkıp geri girince değerler kalıcı olmalı.
2. "Kurye Servisi" switch'ini kapat.
   - Beklenen: Market ekranındaki turuncu motor ikonu **gri** olmalı, basınca "Kurye servisi şu an kapalı" çıkmalı, Paket Gönder ekranı açılmamalı.
3. Switch'i tekrar aç + "Tüm Kullanıcılara İzin Ver"i aç.
   - Beklenen: motor ikonu tekrar turuncu ve tıklanabilir.

## 2) Kullanıcı — Paket Gönder
4. Market ekranından motor ikonuna bas → Paket Gönder ekranı açılmalı.
5. Alım Noktası → haritada bir yer seç/ara → Kaydet.
   - Beklenen: aratılan adres bulunuyor (haritada dışarı atmıyor), Mahalle/Sokak alanları otomatik doluyor.
6. Teslim Noktası için farklı bir konum seç.
   - Beklenen: iki nokta birbirinden farklı kalıyor (biri diğerini ezmiyor).
7. Mesafe ve ücret kartı görünüyor mu (Açılış + km×birim = toplam)?
8. Gönderen adı/telefon, Alıcı adı/telefon, Açık adres (Kat/Daire), açıklama doldur.
9. "Paket Talebini Gönder" bas.
   - Beklenen: bakiyeden ücret düşüyor (Cüzdanım ekranından kontrol et), talep oluşuyor, "gönderildi" mesajı.
10. Bakiyeyi ücretin altına düşürüp tekrar dene.
    - Beklenen: "Yetersiz bakiye" hatası, talep DB'de kalmamalı (silinmeli).
11. AppBar'daki "Geçmiş Paketlerim" ikonuna bas.
    - Beklenen: az önce gönderdiğin talep "Bekliyor" rozetiyle listede.

## 3) Kurye — Bildirim ve Kabul/Red
12. Kurye hesabıyla giriş yap. Adım 9'daki talep için bildirim gelmiş mi (bildirimler ekranı)?
13. Kurye panelinde "Paketler" sekmesine gir.
    - Beklenen: "Bekleyen Talepler" altında talep görünüyor (gönderen, adresler, mesafe, ücret).
14. "Reddet" bas.
    - Beklenen: talep senin listenden kayboluyor. Farklı bir kurye hesabıyla girince talep hâlâ "Bekleyen"de görünmeli.
15. İlk kurye ile tekrar giriş yapıp talebi bu sefer "Kabul Et".
    - Beklenen: "Üzerimdeki Paketler"e taşınıyor. Gönderen kullanıcıya "Kurye Atandı" bildirimi + email gitmiş mi?
16. "Teslim Edildi" bas.
    - Beklenen: talep listeden kayboluyor, gönderene "Teslim Edildi" bildirimi/email gitmiş mi, kuryenin haftalık/aylık kazancına ücret (komisyon düşülmüş) eklenmiş mi (Ana sayfa istatistikleri)?

## 4) Admin — Paketler Sekmesi
17. Kurye Yönetimi → Paketler sekmesine gir.
    - Beklenen: az önceki talep "Teslim Edildi" rozetiyle, **Atanan Kurye: ad + telefon** ile görünüyor (boş liste değil).
18. Farklı durumdaki (Bekliyor/Kurye Yolda/Teslim Edildi) birkaç talep varsa hepsi doğru rozet rengiyle listelenmeli.

## Not düşerken
Her başarısız adım için: adım numarası + gördüğün hata mesajı/ekran görüntüsü + hangi rolle (kullanıcı/kurye/admin) giriş yapmıştın. Bu bana en hızlı teşhisi sağlar.
