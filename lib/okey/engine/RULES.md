# 101 Okey Plus — Kural ve Puanlama Referansı (v2.5)

Bu dosya, `lib/okey/engine/` içindeki kural motorunun ve backend'deki tüm
Okey RPC'lerinin **tek doğruluk kaynağıdır**. Kullanıcının sağladığı
"101 Okey Plus Kapsamlı Oyun Rehberi"ne göre yazılmıştır.

> **v1.0'dan farklar (2026-08-30):** v1.0 yanlışlıkla *standart okey*
> kurallarıyla (15/14 taş, 7 çift bitiş, kapalı el doğrulaması) yazılmıştı.
> v2.0 gerçek **101 Okey Plus** kurallarına geçer: 22/21 taş, 101 puan barajı,
> 5 çift barajı, işleme, okey çalma, katlamalı/eşli modlar, tam ceza sistemi.

---

## 1. Taşlar ve dağıtım

- 4 renk (Kırmızı, Siyah, Mavi, Sarı) × 1–13 × **2 set** = 104 taş
- **2 adet sahte okey** → toplam **106 taş**
- Gösterge: ortaya 1 taş açılır (deste dışı, kimseye dağıtılmaz)
- **Dağıtım: başlayan oyuncuya 22 taş, diğer 3 oyuncuya 21'er taş**
  (22 + 63 = 85 taş dağıtılır, geriye **20 taş** çekme destesi kalır)
- Başlayan oyuncu ilk hamlesinde **çekmeden** doğrudan bir taş atar

### Okey (joker) taşı

- Göstergenin **aynı rengin bir üst rakamı** okeydir (Mavi 7 → Mavi 8; Mavi 13 → Mavi 1)
- **Sahte okey** taşları, okey taşının yerine **normal sayı değeriyle** geçer
  — yani **SERBEST JOKER DEĞİLDİR**. Okey kırmızı 11 ise sahte okey de
  kırmızı 11 sayılır: yalnızca aynı renk 10-11-12 serisine ya da farklı
  renklerden 11-11-11 grubuna girer, başka yere **konulamaz**.
- **Serbest joker yalnızca OKEY taşının 2 kopyasıdır**; onlar her taşın
  yerine geçebilir.
- Sahte okeyi atarak bitirmek "okey atarak bitiş" (×2) **sayılmaz**; okey
  atma/elde kalma cezaları da yalnızca **gerçek okey** için işler.
- Bir elde en fazla 4 joker bulunur: 2 sahte okey + okey taşının 2 kopyası

---

## 2. Geçerli kombinasyonlar

### Seri (per) — aynı renk, ardışık
- En az 3 taş (ör. Siyah 3-4-5)
- **SERİ 13'TE BİTER** — 13'ten sonra sayı gelmez
- `12-13-1` **GEÇERSİZDİR** (sarma yoktur)
- `13-1-2` **GEÇERSİZDİR**
- Biçimsel kural: seri `s, s+1, …, 13` şeklinde ilerler ve `13`'te durur

### Grup — aynı rakam, farklı renk
- 3 veya 4 taş (ör. Kırmızı 8 - Siyah 8 - Mavi 8)
- Aynı grupta **aynı renk iki kez** bulunamaz

### Çift
- **Aynı renk ve aynı rakamdan 2 taş** (ör. 2 adet Kırmızı 5)

---

## 3. El açma (oyuna girme) şartları

### Seri ile açma
- Yere açılacak perlerin **sayı toplamı en az 101** olmalıdır
- Joker, yerine geçtiği taşın değeri kadar puan sayılır
- Seri 13'te bittiği için en yüksek seri `11-12-13` = 36'dır
  > v2.0'da burada "13-1 kombinasyonunda 1 sayısı 1 puan sayılır (12-13-1 = 26)"
  > yazıyordu. Bu, §2'deki "sarma yoktur" kuralıyla ÇELİŞİYORDU ve eski
  > (sarmalı) sürümden kalmıştı. Kod her zaman §2'yi uyguluyor.

### Çift ile açma
- **En az 5 çift (10 taş)** biriktirildiğinde çift olarak el açılabilir
- Çift ile **ilk açılış**, "çifte gidiyorum" beyanını gerektirir (bkz. §7)

### AÇILIŞ TÜRÜNDEN SONRA NE İNDİRİLEBİLİR (v2.4, 2026-09-05)

| Açılış | Seri/grup indirebilir mi? | Çift indirebilir mi? |
|---|---|---|
| **Seri ile açan** | Evet, sınırsız | **Evet — masada başkasının indirdiği bir çift varsa, TUR BAŞINA en çok 3 çift** |
| **Çift ile açan** | **Hayır** (`APP:opening_type_mismatch`) | Evet, sınırsız |

Seri açanın çift indirmesi **açılış türünü değiştirmez**: `opened_with_pairs`
`false` kalır, dolayısıyla §7'nin "çift açıp bitiremeyen ×2" cezası ve
§6'nın "çiftten bitiş ×2" çarpanı o oyuncuya işlemez.

**Hak TUR BAŞINADIR:** oyuncu bir turda 3 çift indirir, sıra masayı dolaşıp
ona döndüğünde yeniden 3 çift indirebilir. El boyunca toplam bir tavan yoktur.

- Ön şart karşılanmazsa: `APP:no_pairs_on_table`
- Turluk 3 çift hakkı aşılırsa: `APP:series_pairs_limit`
- Sınır tek yerde: `okey_series_pairs_limit()` (sunucu) ↔
  `OkeyGameProvider.seriesPairsLimit` (istemci)

> **Turluk sayaç neden `turn_token`e bağlı:** `okey_matches.turn_token`
> yalnızca sıra devrederken üretilir (tek yazan yer:
> `okey_internal_discard_for_seat`), yani turun kimliğidir. Sayaç
> (`okey_player_hands.series_pairs_turn_count`) hangi tur için sayıldığıyla
> (`series_pairs_turn_token`) birlikte tutulur; token eskiyse sayı **sıfır
> sayılır**. Böylece sayaç kendi kendine sıfırlanır ve sıfırlamayı ATLAYAN
> bir yol (el bitişi, deste bitişi, kopmuş oyuncu adına otomatik hamle)
> kalmaz. Aynı hesap istemcide de yapılır
> (`OkeyGameProvider.seriesPairsThisTurn`) — ekrandaki `1/3` rozeti ile
> sunucunun kararı ayrışamaz.

> **Neden ön şart "masadaki çift", "biri çiftle açtı" değil:** rakibin
> `opened_with_pairs` değeri RLS gereği istemciye **kapalıdır**
> (`okey_player_hands`'i yalnızca sahibi okur). Masadaki çiftler ise herkese
> açık. Ölçüt iki tarafta aynı olmasaydı ÇİFT AÇ düğmesi, sunucunun kabul
> edeceği bir hamlede kapalı kalırdı. Ölçüt kendi kendini besleyemez:
> masadaki **ilk** çift zorunlu olarak çiftle açan bir oyuncudan gelir.
>
> **Çift açana neden sınır yok:** onun eli zaten çifttir; 5 çift barajını
> geçmiş bir oyuncuyu 3 çiftle sınırlamak açılışını geri almak olurdu.

### Katlamalı modda baraj
- Açılan her yeni el, masadaki **en yüksek açılış puanından en az 1 fazla** olmalıdır
- İlk oyuncu 101 açtıysa → sonraki en az 102, sonraki en az 103 …
- **105 açan varsa sonraki en az 106** açmalıdır
- Çiftte: biri 5 çift açtıysa → sonraki en az 6 çift açmalıdır

> **İstemci barajı KENDİ hesaplar** (v2.3): formülün iki girdisi de
> (`okey_matches.highest_opening_points` / `_pairs`) maç satırındadır ve
> istemci o satırı zaten okur. Eskiden her tazelemede ayrıca
> `okey_required_opening` RPC'si çağrılıyordu — fazladan bir ağ turu, üstelik
> hata halinde sessizce 101'e düşen (yani katlamalıyı yok sayan) bir yedek
> yolla. Tek istisna **eşli mod**: eşimin `is_opening_done` değeri RLS gereği
> bana kapalı olduğundan, barajın sıfırlanıp sıfırlanmadığını yalnızca sunucu
> bilir; orada RPC korunur.

### ELDEKİ ANLIK PUAN (arayüz, v2.3)

Konsoldaki puan rozeti ve SERİ AÇ rozeti, **el açılmadan önce elimdeki
perlerin toplamını** gösterir (`101` barajına ne kadar kaldı). El açıldıktan
sonra aynı rozet **masaya açtığım puanı** (`okey_matches.open_points`)
gösterir.

Elimdeki puan, ıstaka dizilimine **takılmaz**: `1·2·3` ile `2·2·2` taşları
aralarına boşluk konmadan yan yana dizildiğinde bunlar altı taşlık tek bir
öbektir ve tek başına geçerli bir per değildir. Sayaç öbeğin İÇİNDEKİ geçerli
perleri de arar (`OkeyHandPartitioner.fromRackGroups`), böylece o dizilim
**12** yazar. Aynı hesap SERİ AÇ düğmesini de besler — ekrandaki sayı ile
düğmenin açık/kapalı olması **asla ayrışamaz**.

---

## 4. Taş alma, işleme ve okey çalma

### Yandan (soldaki oyuncudan) taş alma
- Soldaki oyuncunun attığı taşı alan oyuncu, **aynı turda elini açmak
  zorundadır** ve alınan taş açtığı perlerden birinde **kullanılmalıdır**
- Elin zaten açıksa: alınan taş **masadaki açık bir pere işlenmelidir**;
  taş doğrudan ele saklanamaz

Bunlar bir **YÜKÜMLÜLÜKTÜR, izin şartı değil**: taşı almak her zaman
mümkündür, yükümlülüğü yerine getirmeyen ceza öder (aşağı bkz.).

**Nasıl uygulanır — TEK katman: CEZA (v2.2, 2026-09-05)**

Yandan çekme **hiçbir koşulda engellenmez**. Alınan taş o turda gerçekten
kullanılmadıysa (perde/işlemede elden çıkmadıysa) tur bitiminde **+101 ceza**
yazılır (`okey_settings.side_draw_penalty`). Taşı ıskartaya atmak "kullanmak"
sayılmaz.

**ÇİFT İNDİRMEK DE "KULLANMAK"TIR (v2.4):** eli açık bir oyuncu — seri ile
açmış olsun, çift ile açmış olsun — yandan taş çekip onunla **çift
indirebilir**; ceza işlemez. Ölçüt zaten taşın eldeki **kopya sayısının
azalması**, dolayısıyla ayrı bir kod yolu gerekmez. Seri açanın bu hakkı
§3'ün ön şartlarına (masada çift olmalı, tur başına en çok 3 çift) tabidir.

> **v2.1'de bir de "çekme kapısı" vardı** (`APP:discard_tile_not_usable`):
> taş işine yaramıyorsa hamle hiç yapılmıyordu. Kapı ile ceza AYNI ANDA
> yürürlükte olduğu için oyuncu, cezayı göze alsa bile taşı alamıyordu —
> yani ceza fiilen ölü bir kuraldı. Kullanıcı isteğiyle (2026-09-05) kapı
> kaldırıldı; §7'nin kendi çözümü olan ceza tek başına kaldı. Kural zaten
> "hamleyi ENGELLE" değil, "hatalı hamleye +101 yaz" diyordu.

### İşleme
- Eli açık bir oyuncu, sırası geldiğinde uygun taşlarını **kendisinin veya
  rakiplerinin** masadaki açık perlerine ekleyebilir
  (Yerde Mavi 5-6-7 varsa → Mavi 4 veya Mavi 8 işlenebilir)
- **İki uç da geçerlidir** — hem sunucuda (`okey_internal_extend_meld`) hem
  istemcide (`OkeyMeldValidator.extendMeld`). "İŞLE" düğmesinin toplu işleme
  döngüsü 2026-09-05'e kadar bu düzeltmenin DIŞINDA kalmıştı: yalnızca sona
  ekleme deniyordu. Sonuç tam bir çelişkiydi — masada 5-6-7 varken elindeki
  4, atılınca "işlek taş" sayılıp +101 yazıyor, ama İŞLE düğmesi aynı taşı
  "hiçbir pere işlenemiyor" diye geri çeviriyordu

### Okey çalma
- Yerdeki bir seride okeyin yerine geçen **gerçek taş elinde varsa**, sıran
  geldiğinde o taşı yere koyup **okeyi eline alabilirsin**

**Uygulama ayrıntıları** (`okey_steal_joker`):
- Masadaki bir pere dokunmak **işleme yetkisi** ister → **eli açık olmayan
  oyuncu okey çalamaz**
- Hem **seri** hem **grup** perlerinden çalınabilir; per takastan sonra
  **geçerli kalmalıdır** ve joker hangi sıradaysa yeni taş oraya yazılır
- **Sahte okey çalınamaz** — o, perde normal bir taştır (§1)
- El boyutu değişmez (bir taş gider, okey gelir)
- Çalınan okey elde tutulursa el sonunda **okey elde kalma cezası** işler:
  okey çalmak bedava değildir, işlenmesi ya da atılmadan kullanılması gerekir
- Arayüzde ayrı bir mod yoktur: taşı masadaki pere bırakmak/dokunmak önce
  **işlemeyi**, o mümkün değilse **okey çalmayı** dener

---

## 5. Oyun modları

| Mod | Kural |
|---|---|
| **Katlamasız (düz)** | Herkes bağımsız; baraj sabit: 101 puan veya 5 çift |
| **Katlamalı** | Her yeni açılış, masadaki en yüksek açılıştan ≥1 fazla olmalı |
| **Eşsiz (tekli)** | 4 oyuncu bireysel; herkes kendi barajını geçince açar |
| **Eşli (2v2)** | Karşılıklı oturanlar takım (0-2 ve 1-3). Eşlerden biri açtığında **diğer eş baraj aramaksızın** (isterse tek perle) elini açabilir |

Katlamasız/Katlamalı ile Eşsiz/Eşli **birbirinden bağımsız** seçilir (4 kombinasyon).

---

## 6. Bitiş türleri

- **Normal bitiş**: tüm taşları per/işleme olarak yere açıp, **son 1 taşı ıskartaya atarak** bitmek
- **Okey ile bitiş**: son atılan taşın **okey** olması
- **Çiftten bitiş**: çift açan oyuncunun tüm taşlarını çift/işleme olarak tüketip bitmesi
- **Elden bitiş**: hiç el açmadan, **tek turda** tüm taşları serip bitmek

### DESTE BİTERSE: EL, SON ATIŞLA KAPANIR (v2.2)

Çekme destesindeki 20 taş tükendiğinde el **kazanansız** biter ve herkes
elinde kalanların cezasını öder. Kapanma anı, **desteden son taşı çeken
oyuncunun ıskartaya taş atmasıdır** — sıra bir sonraki oyuncuya
*devretmez*.

> **Neden değişti:** eskiden el ancak SIRADAKİ oyuncu boş desteden çekmeye
> *çalışınca* kapanıyordu. Yani son taş atıldıktan sonra masa bir tur daha
> dönüyor, oyuncular elin neden ve ne zaman bittiğini göremiyordu.

### BİTİŞ YALNIZCA ATMA İLE OLUR

Elde **her zaman atılacak en az bir taş kalmalıdır**. Hiçbir açma/işleme
hamlesi eli tamamen boşaltamaz:

| Hamle | Eli boşaltırsa |
|---|---|
| `okey_lay_meld` (per/çift açma) | `APP:must_keep_discard_tile` ile reddedilir |
| `okey_add_to_meld` (işleme) | `APP:must_keep_discard_tile` ile reddedilir |
| Botun açması | eli boşaltacak grup listeden **budanır** |
| Botun işlemesi | son taş işlenmez (`length <= 1` durur) |

> **Neden bu kadar sert:** bu kural yokken elinin tamamını yere seren oyuncunun
> eli 0 taşa iniyor, ama açma fonksiyonu bitişi tespit etmediği için maç
> `in_progress` kalıyordu. Atacak taş olmadığından ne oyuncu ne de otomatik
> oynatma (süre dolumu / kopmuş oyuncu) sırayı ilerletebiliyordu — masa
> **kalıcı olarak kilitleniyor**, giriş ücretleri de dağıtılmadan asılı
> kalıyordu.

---

## 7. Puanlama ve cezalar

| Durum | Puan |
|---|---|
| **Biten oyuncu** | **-101** |
| **Eli açık kalanlar** | Elinde kalan taşların sayı değerleri toplamı (pozitif ceza) |
| **Eli hiç açılmayanlar** | **+202** |
| **Çifte gidip açamayanlar** | **+404** (202'nin 2 katı) |
| **Çift açıp bitiremeyenler** | Elinde kalanların toplamının **2 katı** |
| **Hatalı hamle** | Anında **+101** |

### Bitiş çarpanları (diğer tüm oyuncuların cezaları çarpılır)

| Bitiş türü | Çarpan |
|---|---|
| Normal | ×1 |
| **Okey ile bitiş** | ×2 |
| **Elden bitiş** | ×2 |
| **Çiftten bitiş** | ×2 |
| **Elden + Okey ile** | ×4 (katlanarak) |

> Çarpanlar birleşince **çarpılarak** uygulanır (elden ×2 ve okey ×2 → ×4).

### "Çifte gidiyorum" beyanı

Beyan, 404 cezasının karşılığıdır ve **iki yönlü bir taahhüttür**:

- **Geri alınamaz** — bir kez beyan edilince o el içinde kaldırılamaz
  (`APP:pairs_declaration_locked`)
- **Çift ile ilk açılışın ön koşuludur** (`APP:pairs_declaration_required`)
- Seri ile açmayı **engellemez**: seriyle açan oyuncu "hiç açamayan"
  olmadığından 404 işlemez

> **Neden böyle:** beyan serbestçe geri alınabildiği sürece 404 cezası
> uygulanamaz (oyuncu el bitmeden işareti kaldırır), ayrıca çiftle açmak
> beyan gerektirmediği sürece beyan etmenin oyuncuya **hiçbir faydası
> yoktur** — yani kimse işaretlemez. İkisi birlikte beyanı gerçek bir
> tercihe dönüştürür. Botlar da beyanı **taş çekmeden önce**, başaracağını
> bilmeden verir; "başarınca beyan etme" kaçamağı yoktur.

### Hatalı hamle (+101) sayılan durumlar
- Yere işlenemeyecek taşı atmak — daha doğrusu: masadaki açık bir pere
  **işlenebilecek** taşı ıskartaya atmak (`mistake_discard_penalty`).
  **Atan oyuncunun eli açık olmak zorunda DEĞİLDİR** (v2.5, 2026-09-07):
  ölçüt taşın masada işlenebilir olmasıdır, atanın işleme yetkisi değil.
  > 20260903000001 cezayı `is_opening_done` koşuluna bağlamıştı ve kural
  > fiilen ölmüştü: canlı hamle kayıtlarında oyuncuların attığı işlek
  > taşların tamamına yakını el açılmadan ÖNCE atılıyor, dolayısıyla hiç
  > ceza yazılmıyordu. Koşul 20260907000003 ile kaldırıldı; istemcideki
  > kırmızı uyarı (`OkeyGameProvider._isTileProcessableOntoTable`) da aynı
  > anda hizalandı — uyarı ile ceza asla ayrışamaz.
  >
  > Botlar bu değişiklikten etkilenmez: 20260905000005'ten beri işlek taş
  > atmayı zaten son çare olarak bırakıyorlar.
- Açamayacağı halde yandan taş çekmek → alınan taşı o turda kullanmamak
  (`side_draw_penalty`, bkz. §4)
- Diğer kural dışı hamleler

**Cezaların üst üste binmemesi:**

| Durum | Uygulanan |
|---|---|
| Okey atmak (üstelik işlenebilirdi) | yalnızca **okey atma cezası** — daha özel kural kazanır, 202 olmaz |
| Süre dolumu / kopmuş oyuncu adına **otomatik** atma | okey ve işlek taş cezası **YAZILMAZ** (taşı oyuncu seçmedi) |
| Otomatik atmada yandan çekme cezası | **YAZILIR** — o taşı yandan almak oyuncunun kendi kararıydı |

---

## 8. Uygulama notları (motor ↔ backend sözleşmesi)

- Kazanma, ayrı bir "kazandım" beyanıyla değil, **eli boşaltıp son taşı atmakla**
  gerçekleşir — sunucu her atmadan sonra eli kontrol eder. Başka hiçbir hamle
  (açma, işleme) bitiş sayılmaz (bkz. §6)
- Tüm doğrulama (açma barajı, işleme geçerliliği, okey çalma, bitiş) **sunucuda**
  yapılır; istemcideki Dart motoru yalnızca UI ipucu içindir, asla güvenilmez
- `okey_table_melds.meld_type`: `run` | `set` | `pair` | `gosterge`
- `okey_moves.action`: `draw_deck` | `draw_discard` | `discard` |
  `timeout_auto_discard` | `lay_meld` | `add_to_meld` | `steal_okey` |
  `declare_win`
- **Ekonomi:** maçın ilk elinde **masa puanı** tahsil edilir
  (`okey_internal_collect_entry_fees`), maç bitince pot kazanan(lar)a
  dağıtılır (`okey_internal_award_match`). Beraberlikte pot **paylaşılır**;
  kazananların tamamı bot ise net pot `okey_house_revenue`'ya
  `unclaimed_pot` olarak yazılır (yok sayılmaz)
- **MASA PUANI = giriş puanı × el sayısı** (v2.2). `okey_rooms.entry_fee`
  EL BAŞINA puandır; masaya girmenin gerçek bedeli üretilmiş
  `okey_rooms.table_stake` sütunudur. Tahsilat, pot ve bakiye kontrolleri
  daima `table_stake` kullanır — 3 el × 500 = 1.500
- **ANLIK PER PUANI** (v2.2): her koltuğun bu elde masaya açtığı ve
  işlediği taşların toplamı `okey_matches.open_points` içinde tutulur ve
  masadaki herkes görür. Per açmak (`okey_lay_meld`) ve taş işlemek
  (`okey_add_to_meld`) bu sayacı büyütür. **Ceza değildir**
  (`okey_matches.scores` ayrı bir şeydir): açık puan yüksek olsun istenir,
  ceza düşük

---

## §8 — GÖSTERGE ÇİFTİ ve OKEY CEZALARI (v2.1)

### Gösterge çifti
Göstergenin bir kopyası ortada **açık** durduğu için oyunda yalnızca **bir**
kopyası kalır — gerçek çiftini yapmak imkânsızdır. Bu yüzden göstergeyle aynı
taşı elinde tutan oyuncu, o **tek taşı başlı başına bir çift** olarak indirir.

> Örnek: elinde 4 gerçek çift olan oyuncu, göstergeyle birlikte **5 çift**
> sayılır ve çiftle açabilir.

İndirilen gösterge çifti masada ayrı bir tür olarak (`gosterge`) durur ve
**üzerine işleme yapılamaz** — tek taştan oluşur, tamamlanamaz.

> **Uygulama notu (2026-09-05):** perlerin/çiftlerin otomatik sayımı
> ıstakadaki BİTİŞİK ÖBEKLER üzerine kuruludur
> (`OkeyRackLayout.contiguousGroups`): iki yanında boşluk olmayan hiçbir şey
> çift sayılmaz. Bu yüzden `groupByPairs` gösterge taşını ve joker çiftlerini
> kendi öbeklerine AYIRMAK zorundadır. Ayırmadığı sürece kural kâğıt
> üzerinde var, masada yoktu: 4 gerçek çifti olan oyuncu 5. çifti hiç
> göremiyor, ÇİFT AÇ düğmesi sönük kalıyordu.
Normal çiftlere (`pair`) de işleme yapılamaz; işleme yalnızca seri (`run`) ve
gruplara (`set`) yapılır.

### Okey cezaları
Okey taşı ne atılabilir ne de saklanabilir; işlenmek zorundadır.

| Durum | Ceza |
|---|---|
| Okeyi ıskartaya **atmak** | +101 (`okey_settings.okey_discard_penalty`) |
| El bittiğinde okey **hâlâ elde** | +101 (`okey_settings.okey_in_hand_penalty`) |

İki ceza da admin panelinden ayrı ayrı ayarlanabilir ve el sonunda oyuncunun
skoruna eklenir. Kazanan bile okey attıysa/elinde tuttuysa cezasını öder.

### Bot yetkileri
Botlar gerçek oyuncularla aynı kurallara tabidir ve aynı hamleleri yapar:

- Soldakinin ıskartasından ya da desteden çeker. **Yandan yalnızca taşı
  gerçekten kullanacaksa alır** (eli açıksa masadaki bir pere işleyecekse
  **ya da onunla çift indirebilecekse**, açık değilse o taşla BU TURDA
  açabilecekse) — böylece §4 cezasına düşmez
- Seri/grup açar, **çift de açabilir**; çiftle açacaksa beyanı **taş çekmeden
  önce**, henüz başaracağını bilmeden verir (404 riskini gerçekten üstlenir)
- **Seri ile açmışsa §3'ün turluk 3 çift hakkını da kullanır** — kural tek yerde
  (`okey_internal_lay_pairs_for_seat`) durduğu için bot fazladan bir denetim
  taşımaz: hakkı yoksa çağrı `false` döner
- Masadaki açık perlere taş işler, ama **son taşını işlemez** (bitiş atmayladır)
- Okeyi asla atmaz
- **Okey çalmaz** — bilinçli sadeleştirme: karar ağacını belirgin biçimde
  büyütür, kazanma şansına katkısı küçüktür

Bot hamlesini masadaki herhangi bir istemci tetikler; tetikleme **sıra
kimliğini (`turn_token`) taşır**, böylece bayat bir zamanlayıcı artık sırası
gelmiş BAŞKA bir botu gecikmesiz oynatamaz.
