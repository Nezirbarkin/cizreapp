# Supabase Database Yedekleme Rehberi

## Adım 1: Supabase Dashboard'a Giriş

1. Tarayıcıda [https://supabase.com/dashboard](https://supabase.com/dashboard) adresine gidin
2. GitHub hesabınızla veya e-postanızla giriş yapın
3. Projeler sayfasında **"CizreApp"** projenizi seçin

## Adım 2: Database Bölümüne Git

1. Sol kenar çubuğunda **"Database"** sekmesine tıklayın
2. Bu bölümde veritabanı tablolarınızı, replikasyon ayarlarını ve yedekleri görebilirsiniz

## Adım 3: Backups Sekmesine Geç

1. Database sayfasında üst menüde **"Backups"** sekmesine tıklayın
2. Mevcut otomatik yedekler listelenir (genellikle son 7 gün)

## Adım 4: Manuel Yedek Oluştur

1. Sayfanın sağ üst köşesinde **"+ New Backup"** veya **"Create Manual Backup"** butonuna tıklayın
2. Yedekleme işlemi birkaç dakika sürebilir
3. "Status" sütununda "Completed" göründüğünde yedek hazır

## Adım 5: Yedeği İndir

1. Oluşturulan yedeğin satırında sağ tarafta **"Download"** butonunu görün
2. Tıklayarak SQL dosyasını indirin
3. Dosyayı güvenli bir yere (bulut depolama, harici disk) kaydedin

## Önemli Notlar

- **Ücretsiz plan**: Sadece son 7 günün otomatik yedeği saklanır
- **Pro plan**: Daha uzun yedekleme süresi ve daha fazla yedek seçeneği
- **Manuel yedek**: Her zaman en güncel veritabanı durumunu içerir
- Yedek dosyasını projenizdeki `backups/` klasörüne kaydedebilirsiniz

## Özet Görsel Adımlar

```
Dashboard → Projects → CizreApp → Database → Backups → Create Manual Backup → Download
```
