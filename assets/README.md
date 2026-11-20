# Görseller, ikonlar ve sesler

Bu klasördeki her şey Optik için özgün üretildi ve doğrudan kullanılabilir. Renk ve ölçülerin tek kaynağı `tasarim-tokenlari.json`.

## İçerik

| Klasör / dosya | Ne | Nasıl kullanılır |
| :-- | :-- | :-- |
| `karakter/svg/optik-<ruh hali>.svg` | 8 durağan poz: bekliyor, mutlu, dinliyor, dusunceli, uyari, kutlama, uykulu, soru. Katmanlar kimlikli: `golge`, `ic-duvar`, `bacak-sol`, `bacak-sag`, `kabuk`, `catlaklar`, `gozler`, `gaga`, `ekler` | Ölçü kaynağı. Bildirim görseli, boş durum, belge. Görünüm kutusu `-10 -30 200 240` (karakter kutusu 180 × 200, çevresinde zıplama ve ek payı). |
| `karakter/png/` | Aynı pozlar, saydam, 200 × 240 pt, @1x @2x @3x | Hızlı kullanım, bildirim eki, mobil |
| `karakter/optik-ruh-halleri.png` | Bütün ruh halleri tek görselde | Göz atmak için |
| `animasyon/optik.css` | Karakterin tam geometrisi, ruh halleri ve bütün anahtar kareler | Zamanlama ve hareket kaynağı. Web yüzeyi olursa doğrudan kullanılır |
| `animasyon/optik-demo.html` | Çalışan referans: ruh hallerine bas, hareketi ve sesi oynat | Tarayıcıda aç. `#mutlu` gibi adres eki ile doğrudan bir ruh hali açılır |
| `kumes/` | Kümes kapısı, kapalı ve açık, SVG + PNG | Çentik adacığı |
| `ikon/optik-uygulama-ikonu.svg`, `-1024.png` | Uygulama ikonu ana dosyası | |
| `ikon/AppIcon.appiconset/` | macOS ikon seti (16–512 pt, @1x @2x) ve `Contents.json` | Xcode `Assets.xcassets` içine olduğu gibi kopyala |
| `ikon/menubar-sablon.svg`, `.png`, `@2x.png` | Menü çubuğu ikonu, tek renk, 18 pt | `isTemplate = true` olarak yükle |
| `arayuz-ikonlari/*.svg` | 15 çizgi ikon, 24 × 24, `currentColor` | Sekme ve düğme ikonları. Xcode'da "Preserve Vector Data" + "Template Image" |
| `sesler/*.wav` | 9 ses efekti, 44,1 kHz, 16 bit, mono | Tablo: `docs/03-karakter.md` bölüm 7 |
| `sesler/konusma/*.wav` | 18 sabit cümle, Jessica (ElevenLabs) sesiyle, 44,1 kHz, 16 bit, mono. CC BY 4.0 dışında, ElevenLabs atfıyla, ticari olmayan kullanım. Kişiye özel ses seçen kullanıcının cümleleri buraya değil, kendi Mac'inde `Application Support` altına yazılır | `sesler/konusma/OKU.txt`, `llm/sabit-cumleler.json`, `llm/ses-kimligi.md` |
| `tasarim-tokenlari.json`, `.css` | Renk, yazı, köşe, boşluk, adacık ölçüleri, hareket süreleri | Koda sabit olarak taşı |

## Pakette olmayanlar

- **Yazı tipleri.** Space Grotesk ve Inter (ikisi de SIL Open Font License). Google Fonts'tan indirip uygulamaya göm.
- **Optik'in canlı konuşma sesi.** Sabit cümleler hazır; geri kalanı ElevenLabs API anahtarıyla akışla üretilir (varsayılan ses Jessica). Tarifi `llm/ses-kimligi.md` içinde.
- **Ekran görüntüleri.** Ekran tasarımlarının kaynak dosyaları `tasarim-kaynak/` içinde, tarifleri `docs/01-urun.md` içinde.

## Kurallar

- Karakterin biçimini, oranlarını ve renklerini değiştirme. Yalnızca vurgu rengi (bacaklar, gaga) kullanıcı ayarıdır.
- Karakter koyu zemin (`#12131C`) ve siyah adacık üstünde tasarlandı. Açık zeminde kullanılacaksa gölgeyi koyulaştırma, kabuğa 1 pt `#DDD0BA` kenar ekle.
- En küçük kullanım: 32 pt yükseklik. Daha küçükte menü çubuğu şablon ikonunu kullan.
- Dosyaları yeniden üretmek gerekirse ölçüler `docs/03-karakter.md` bölüm 1'de.
