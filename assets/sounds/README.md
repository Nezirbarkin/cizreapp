# Okey ses efektleri

Bu klasördeki dosyalar oyunun **örnek (varsayılan) ses seti**dir ve depoya
dahildir. Admin panelinden (`101 Okey Yönetimi → Sesler`) hiçbir dosya
yüklenmemişse oyun bu sesleri çalar; admin panelindeki 🎚 düğmesi de tam
olarak bu dosyaları dinletir.

## Ses kaynağı sırası

1. Admin panelinden yüklenmiş dosya (uzak URL) — varsa **her zaman** bu çalar.
2. Buradaki örnek dosya (`assets/sounds/*.wav`).
3. İkisi de çalınamazsa dokunsal geri bildirim (titreşim).

Bkz. `lib/okey/services/okey_sound_service.dart`.

## Dosyalar

| Dosya | Ne zaman çalar | Nasıl üretildi |
|---|---|---|
| `draw.wav` | Desteden veya ıskartadan taş çekilince | sürtünme gürültüsü + taş moduları |
| `discard.wav` | Taş ıskartaya atılınca | taş modları + masanın ahşap tepkisi |
| `meld.wav` | Masaya per/grup açılınca | art arda üç taş, düzensiz aralıklarla |
| `process.wav` | Masadaki bir pere taş işlenince | çift temas (taş taşa değiyor) |
| `your_turn.wav` | Sıra sana gelince | cam zil — inharmonik kısmi tonlar |
| `time_warning.wav` | Sıra süresinin son 5 saniyesinde | hızlanan saat tik-tak'ı |
| `win.wav` | Eli sen kazanınca | alkış (95 ayrı el çırpma) + zil motifi |
| `lose.wav` | Eli rakip kazanınca | inen çekiçli telli çalgı üçlüsü |
| `laugh.wav` | Rakip "işlek" bir taş atınca — alay efekti | formant vokal sentezi ("ha ha ha") |
| `error.wav` | Geçersiz hamle / hata | modüle edilmiş testere dalgası zili |

## Nasıl üretildiler

`scripts/generate_okey_sounds.py` — bağımlılık gerektirmez, yalnızca Python
standart kütüphanesi:

```bash
python scripts/generate_okey_sounds.py
```

Sentez basit sinüs "bip"leri değil, fiziksel modelleme kullanır:

- **Taş sesleri** — modal sentez: kısa bir kuvvet darbesi, paralel rezonatör
  bankasını (620 Hz–7.4 kHz arası altı inharmonik mod) uyarır.
- **Kahkaha** — formant sentezi: Rosenberg glotal darbe dizisi, /a/ ünlüsünün
  formantlarından (730 / 1090 / 2440 / 3400 Hz) geçirilir.
- **Alkış** — tek tek el çırpmaların istatistiksel toplamı; her biri kendi
  bant genişliğine sahip kısa bir gürültü darbesi.
- **Zil ve piyano** — inharmonik kısmi tonlar, kısmi tona özel sönümleme
  süreleri, tokmak/çekiç gürültüsü.
- **Mekan** — Schroeder reverb (comb + allpass).

Çıktı 44.1 kHz 16-bit mono WAV (toplam ~713 KB). Tüm dosyalar ileri bakışlı
limitleyiciden geçirilip **15 ms pencerede −15 dBFS**'e eşitlenmiştir: hiçbiri
diğerinin önüne geçmez, hiçbirinde kırpma yoktur.

## Değiştirmek

Kalıcı olarak değiştirmek için buradaki dosyaların üzerine yazın (dosya adları
`OkeySound.fileName` ile eşleşmek **zorunda**) ya da üretici betiğin
parametrelerini düzenleyip yeniden çalıştırın. Tek bir kurulumda değiştirmek
için admin panelinden yükleyin — uygulama güncellemesi gerektirmez, tüm
oyunculara anında uygulanır.

`pubspec.yaml` içindeki `assets:` bölümünde `- assets/sounds/` satırı zaten
mevcuttur.
