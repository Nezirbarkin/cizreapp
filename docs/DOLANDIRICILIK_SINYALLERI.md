# Dolandırıcılık Sinyalleri

Bu modül otomatik ceza vermez. Veriler yalnızca admin incelemesi için risk
göstergesi üretir; hesap kısıtlama gibi kararlar insan değerlendirmesiyle
alınmalıdır.

## Algılanan sinyaller

| Sinyal | Varsayılan eşik |
|---|---|
| Çoklu hesap | Normalize edilmiş aynı telefonun en az 2 profilde bulunması |
| Sıra dışı iade | 90 günde en az 3 iade ve teslim edilen siparişlere göre %50+ oran |
| Kupon suistimali | 7 günde 5+ kullanım veya toplam 1.000 TL+ indirim |
| Sahte değerlendirme | 24 saatte 5+ yorum ve yorumların %80+ oranında 1/5 puan olması |

Eşikler ilk güvenli sürüm için açıklanabilir ve ihtiyatlı tutulmuştur. Gerçek
veri dağılımı gözlendikten sonra migration içindeki tarama fonksiyonunda
güncellenmelidir.

## Kurulum ve kullanım

1. `20260729000004_fraud_detection_system.sql` migration'ını uygulayın.
2. Admin panelinden **Dolandırıcılık Sinyalleri** bölümünü açın.
3. **Risk Taraması Başlat** düğmesine basın.
4. Sinyali açık, inceleniyor, onaylandı veya reddedildi olarak işaretleyin ve
   karar gerekçesini admin notuna yazın.

Onaylanan sinyaller mevcut `profiles.is_suspicious` işaretini de etkinleştirir.
Reddedilen sinyaller yeni olay tekrar oluşursa yeniden açılır.

## Güvenlik ve gizlilik

- Tablo erişimi istemcilere kapalıdır; işlemler yalnızca admin rolünü sunucuda
  doğrulayan `SECURITY DEFINER` RPC'leri üzerinden yapılır.
- Telefon numarası kanıt alanına yazılmaz; sinyal parmak izinde SHA-256 özeti
  kullanılır.
- Risk puanı tek başına suç veya kötü niyet kanıtı değildir.
- Admin notlarında gereksiz kişisel veri tutulmamalıdır.

## Operasyon önerisi

İlk aşamada tarama admin tarafından manuel çalıştırılır. Veri hacmi büyüdüğünde
`admin_scan_fraud_signals()` günlük Supabase Cron görevi olarak service-role
üzerinden çağrılabilir. İstemciye service-role anahtarı kesinlikle eklenmemelidir.
