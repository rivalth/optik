# Karakter: Optik

Optik özgün bir karakterdir: krem rengi bir yumurta. Kabuğun altı zikzak kırılmış, kırıktan iki turuncu civciv ayağı çıkıyor. Kabuğun önündeki düzensiz çatlaktan içerideki civcivin iki gözü ve gagası görünüyor. Yüz ifadesi yalnızca bu çatlaktan ve vücut hareketinden okunur.

Kaynak dosyalar:

- Çalışan referans: `assets/animasyon/optik-demo.html` (tarayıcıda aç, ruh hallerine bas).
- Geometri ve animasyonların tamamı: `assets/animasyon/optik.css`.
- Durağan pozlar: `assets/karakter/svg/optik-*.svg` (katman kimlikleriyle) ve `assets/karakter/png/`.

Yerel uygulamada karakter SwiftUI `Shape` ve Core Animation ile yeniden çizilir. SVG ve CSS dosyaları ölçü ve zamanlama kaynağıdır, uygulamaya gömülmez (ikon ve durağan görseller hariç).

## 1. Tasarım kutusu ve katmanlar

Kutu 180 × 200 birim. Koordinatlar sol üstten. Çizim sırası alttan üste:

| # | Katman | Geometri | Renk |
| :-- | :-- | :-- | :-- |
| 1 | Gölge | elips, merkez (90, 190), 90 × 12 | siyah, %40 |
| 2 | İç duvar | elips, merkez (90, 137), 92 × 22 | `#A3957F` |
| 3 | Sol bacak | çizgi (73,146)→(73,178), parmaklar (62,187) (73,188) (84,187), kalınlık 5, yuvarlak uç | vurgu |
| 4 | Sağ bacak | aynısı, x = 107 | vurgu |
| 5 | Kabuk | 120 × 156, sol üst (30, 6). Üst yarı elips yarıçapı 60 × 96,72, alt yarı 60 × 59,28. Alt kenar zikzak kesik | `#F4EDE0` |
| 6 | Kabuk gölgesi | kabuğun sağ alt kenarında içe doğru (-10, -12) kaydırılmış hilal | siyah, %7 |
| 7 | Benekler | (55.5, 43.5) r 3.5, (122.5, 36.5) r 2.5, (127, 109) r 3 | `#DDD0BA` |
| 8 | Çatlak çizgileri | (119,66)→(128,60)→(131,51) ve (62,86)→(54,92)→(52,101), kalınlık 1.6 | `#CFC2AC` |
| 9 | Delik | 68 × 40 kutuda düzensiz çokgen, kutunun sol üstü (56, 56) | `#2A2521` |
| 10 | Gözler | varsayılan 10 × 13, köşe 5, merkezler (78.5, 71) ve (101.5, 71) | `#FFF4D6` |
| 11 | Gaga | üçgen (85,81) (95,81) (90,88) | vurgu |
| 12 | Ekler | pullar, "z" harfleri, ünlem (yalnızca ilgili ruh halinde) | nane / vurgu |

Zikzak kesik (kabuk kutusunun yüzdesi olarak): `0 0, 100 0, 100 80, 90 87, 80 79, 69 88, 58 80, 47 89, 36 80, 25 88, 15 79, 6 86, 0 80`.

Delik çokgeni (delik kutusunun yüzdesi olarak): `100 50, 87.5 66.7, 81.2 87.2, 58.3 89.1, 38.5 96.1, 22.4 81.7, 3.6 68.7, 7.1 47.7, 6.3 27.8, 25.4 18.5, 41.1 4.4, 60 9.7, 81.2 11.5, 88.5 32`.

Gözler ve gaga deliğin içinde kırpılır. Delik şekli bilerek düzensiz ve asimetriktir, simetrik ya da sivri kanatlı hale getirme.

## 2. Hareket grupları

| Grup | İçerir | Dönüş merkezi |
| :-- | :-- | :-- |
| `dokun` | her şey (gölge hariç) | (90, 192) alt orta |
| `hareket` | her şey (gölge hariç) | (90, 192) |
| `salin` | iç duvar + kabuk (bacaklar hariç) | (90, 160) |
| `bacak` | tek bacak | bacağın üst ucu (x, 144) |
| `goz-sar` | tek göz (kırpma için) | gözün merkezi |

Bacaklar `salin` grubunun dışındadır: gövde sallanırken ayaklar yerde kalır.

## 3. Ruh halleri

| Ruh hali | Ne zaman | Gözler | Gövde | Bacaklar | Ek | Ses |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `bekliyor` | varsayılan | 10 × 13 oval, 4,2 sn'de bir kırpar | 2,8 sn'de hafif salınır (±1,5°, 3 birim yukarı) | sabit | yok | `tik` |
| `mutlu` | gün yolundayken | 10 × 7 kubbe (üstü yuvarlak, altı düz) | 1 sn'de ±5° sallanır | sırayla 7 birim kalkar | yok | `mutlu` |
| `dinliyor` | uyandığında, konuşurken | 11 × 14 | -8° öne eğilir | sabit | gaga 0,3 sn'de açılıp kapanır | `dinliyor` |
| `dusunceli` | plan yaparken, işlem sürerken | (3, -3) kayar, sağ göz 9 yüksekliğinde | 2,6 sn'de -6° ile 4° arası | sağ ayak 0,6 sn'de -14° tempo tutar | yok | `dusunceli` |
| `uyari` | yaklaşan ya da geciken bir şey varken | 12 × 12 daire | 1,4 sn'de bir titrer | 0,36 sn'de hızlı adım | turuncu ünlem yanıp söner, gaga 1,6 kat | `uyari` |
| `kutlama` | bir iş bitince | 11 × 11 kare, 45° döndürülmüş, parlar | 0,72 sn'de 26 birim zıplar, ezilip uzar | zıplarken ±30° iki yana açılır | 4 pul saçılır, gaga 1,5 kat | `kutlama` |
| `uykulu` | gün bitince, adacık kapalıyken | 12 × 3 çizgi, kırpma yok | 36 birim aşağı iner (yere oturur), yavaş nefes | 0,3 katına kısalır (kabuğun içine çekilir) | "z" harfleri yükselir | `uykulu` |

Dokunma ya da tetikleme zıplaması: 0,55 sn, önce ezilir (1.1 × 0.86), sonra 18 birim sıçrar, yerine oturur. Her ruh hali değişiminde bir kez oynar.

Geçiş kuralları:

- Göz ve gaga biçimleri 0,28 sn'de, hafif taşan bir eğriyle (`cubic-bezier(.3,1.5,.5,1)`) değişir.
- `kutlama` ve dokunma tepkisi geçicidir: 2 ile 2,8 sn sonra ekranın asıl ruh haline döner.
- "Hareketi azalt" sistem ayarı açıksa bütün döngüsel animasyonlar durur, yalnızca göz ve gaga biçimi değişir.

Tam anahtar kareler `assets/animasyon/optik.css` içinde, adları `optik-` ile başlar.

## 4. Kümes ve adacık

- Kümes kapısı 48 × 58 birim: kemerli çerçeve `#5A3A1E`, içi `#1E140B`, kanat `#B07A42` (iki tahta çizgisi, yuvarlak pencere), dibinde üç saman çöpü `#E9C46A`.
- Bekleme halinde kapı 0,44 ölçekte adacığın sol kanadında (16, 5) konumunda durur. Açık halde tam ölçekte (24, 80) konumuna iner.
- Kapı kanadı sol kenarından 108° döner (0,35 sn).
- Optik kapının arkasından çıkar: (-50, 30) kayık ve 0,15 ölçekten kendi yerine, 0,5 sn, 0,25 sn gecikmeyle, taşan eğriyle. Dönerken aynı yol tersine.
- Adacık içinde Optik 0,5 ölçekte (90 × 100 pt) durur, gölgesi çizilmez.
- Görseller: `assets/kumes/`.

## 5. Renkler

`assets/tasarim-tokenlari.json` tek kaynaktır.

| Ad | Değer | Kullanım |
| :-- | :-- | :-- |
| zemin | `#12131C` | pencere arka planı |
| yüzey | `#1C1E2B` | kartlar, alt çubuk, konuşma balonu |
| yüzey-2 | `#262939` | ikincil düğme, boş ilerleme çubuğu |
| metin | `#F2F0E9` | ana metin |
| metin-soluk | `#A3A6B8` | ikincil metin |
| çizgi | `#5B5F78` | kesik kenarlık, etiket çerçevesi |
| çizgi-güçlü | `#7A7F9C` | işaret kutusu çerçevesi |
| vurgu | `#FF8A3D` | birincil düğme, seçili gün, bacak ve gaga, uyarı |
| nane | `#5EE0C8` | tamamlandı, ilerleme, seçili sekme, mikrofon noktası |
| adacık | `#000000` | çentik adacığı |

Vurgu rengi kullanıcı ayarıdır (`#FF8A3D`, `#7C9BFF`, `#F25F8B`, `#E9C46A`). Uyarı işareti her zaman `#FF8A3D` kalır.

Kurallar: vurgu ve nane üstündeki metin `#12131C`. Durum yalnızca renkle anlatılmaz, yanında işaret ya da yazı olur.

## 6. Yazı

- Başlık ve sayılar: Space Grotesk 700 (yedek: sistem yazı tipi, yuvarlak olmayan).
- Metin: Inter 400 / 600 (yedek: sistem yazı tipi).
- Boyutlar: ekran başlığı 26, bölüm başlığı 18, kart başlığı 15–16, ikincil 13, etiket 11.
- İki yazı tipi de SIL Open Font License ile dağıtılır. Dosyalar pakette yok, Google Fonts'tan indirilip uygulamaya gömülmeli.

## 7. Ses efektleri

`assets/sesler/` altında, 44,1 kHz, 16 bit, mono WAV. Hepsi sentezlenmiş özgün seslerdir.

| Dosya | Süre | Tarif | Ne zaman |
| :-- | :-- | :-- | :-- |
| `tik.wav` | 70 ms | kabuğa tek vuruş | sekme, seçim, geri al |
| `uyan.wav` | 380 ms | iki vuruş + soran cıvıltı | uyandırma kelimesi algılandı ("Efendim?" sesinden hemen önce) |
| `dinliyor.wav` | 180 ms | yükselen tek cıvıltı | dokunma, dinlemeye geçiş |
| `mutlu.wav` | 230 ms | iki kısa cıvıltı | ses açıldı, olumlu yanıt |
| `dusunceli.wav` | 380 ms | alçak mırıltı, önce yükselir sonra iner | işlem uzadı |
| `uyari.wav` | 440 ms | üç vuruş + inen cıvıltı | hatırlatıcı, sınır aşıldı |
| `tamam.wav` | 200 ms | vuruş + yükselen cıvıltı | kayıt yapıldı |
| `kutlama.wav` | 470 ms | dört tırmanan cıvıltı | iş bitti, ödeme alındı |
| `uykulu.wav` | 640 ms | uzun inen ton | gün kapandı |

Ses efekti ile konuşma üst üste binmez: efekt önce çalar, konuşma 60 ms sonra başlar. Ses kapalıyken ikisi de susar, görsel tepki devam eder.
