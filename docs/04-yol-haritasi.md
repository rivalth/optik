# Yol haritası

Her aşama kendi başına çalışan bir şey bırakır. Bir aşamanın kabul kriterleri sağlanmadan sonrakine geçme.

## Aşama 0: İskelet ve karakter

- Xcode projesi, `OptikCore` paketi, menü çubuğu ajanı, boş ayarlar penceresi.
- Tasarım tokenları koda taşınır (`assets/tasarim-tokenlari.json`).
- `OptikView`: karakter SwiftUI ile çizilir, yedi ruh hali ve dokunma zıplaması çalışır. Ses efektleri bağlanır.
- Bir önizleme penceresi: bütün ruh halleri yan yana.

**Kabul:** önizleme penceresi `assets/animasyon/optik-demo.html` ile yan yana konduğunda biçim, renk ve zamanlama aynı. 120 Hz ekranda kare düşmüyor. "Hareketi azalt" açıkken döngüler duruyor.

## Aşama 1: Çentik adacığı ve kümes

- `NSPanel`, çentik ölçüsü hesabı, çentiksiz ekranda yüzen hap.
- Adacık durum makinesi: bekliyor → efendim → dinliyor → yanıtlıyor → bekliyor.
- Kümes kapısı, Optik'in çıkış ve dönüş animasyonu.
- Genel klavye kısayolu ile tetikleme. "Efendim?" şimdilik sistem sesiyle.

**Kabul:** kısayola basınca adacık 100 ms içinde açılmaya başlıyor. Tam ekran uygulamada kendiliğinden çıkmıyor. Dış ekran takılıp çıkarıldığında konumu doğru. Boşta CPU %1 altında.

## Aşama 2: Ses hattı

- ✅ Mikrofon izni, 16 kHz yakalama, yankı giderme, VAD (arka plan sesini ayırır).
- ✅ `Transcriber` (WhisperKit), kısmi metin adacıkta.
- ✅ `LLMClient` (Claude, akış), araçsız kısa sohbet. Anahtar yokken duyduğunu tekrar eder.
- ✅ `SpeechSynthesizer` (ElevenLabs, Jessica): sabit cümleler dosyadan, değişken yanıt akışla. Önbellek henüz yok.
- Ayarlarda kişiye özel ElevenLabs sesi: ses kimliği gir, sabit cümleleri yerelde yeniden üret, varsayılana dön.
- `WakeWordDetector`: önce doğrulama (bkz. mimari 3.1), sonra bağlama.
- ✅ Gecikme ölçümü. Kayıt şimdilik sistem günlüğüne, aşama 3'te `conversation_log`'a.

**Kabul:** "Optik" → ilk ses (`uyan` efekti) 250 ms altı, "Efendim?" hemen ardından. "Saat kaç?" gibi bir soruda konuşma sonu → ilk ses 1,5 sn altı (10 denemenin ortancası). Optik konuşurken söz kesilince susuyor. Ağ yokken anlaşılır biçimde bildiriyor. 30 dakikalık ortam sesinde en fazla 1 yanlış tetikleme.

## Aşama 3: Veri ve günlük hayat

- GRDB, `veri/sema.sql`, göçler, örnek veri yükleyici (yalnızca geliştirme derlemesinde).
- Araç yürütücü ve ilk araçlar: etkinlik, görev, kişi, not, hatırlatıcı.
- Pencere bölümleri: Bugün, Takvim, Kişiler, Dersler, Projeler.
- Tek cümleyle kayıt ve geri al.

**Kabul:** `docs/01-urun.md` bölüm 4'teki örnek cümlelerden para ile ilgili olmayanların hepsi doğru yere yazılıyor. Geri al çalışıyor. Bir bölümde yapılan değişiklik diğerlerine anında yansıyor.

## Aşama 4: Para, ilişki, müşteriler

- Bütçe, kategoriler, harcama, nakit akışı takvimi.
- İlişki bölümü, önemli günler.
- Müşteriler, teklifler, siparişler, kilometre taşları, ödemeler, masraflar.
- Teklif → sipariş dönüşümü ve ödeme planı şablonları.
- Para ve İlişki için Touch ID kilidi.

**Kabul:** bölüm 4'teki para cümlelerinin hepsi doğru. Kilometre taşı tamamlanınca bağlı ödeme "vadesi geldi" oluyor, ödeme alınınca kalan tutar düşüyor. Kuruş hesabında yuvarlama hatası yok (testle). Kilitliyken LLM isteğinde bu veriler yok (testle).

## Aşama 5: Optik haber verir

- Kural motoru ve ilk kural seti (bölüm 5.2).
- Zamanlayıcı, hatırlatıcılar, haber verme önceliği.
- Sabah brifingi, akşam kapanışı.
- Haftalık ve aylık rapor, haftalık planlama.

**Kabul:** her kuralın birim testi var. Sunum ya da tam ekranda bildirim bekliyor. Geçilen öneri 7 gün gelmiyor. Brifing 20 saniyeyi aşmıyor.

## Aşama 6: Derinlik

- Fiş fotoğrafından harcama.
- Hafıza araması.
- Sistem takvimiyle iki yönlü eşleme (EventKit).
- Yedekleme ve dışa aktarma (JSON, CSV).

## Aşama 7: Mobil eşlikçi

- Senkron servisi.
- Telefon uygulaması: Bugün, Özet, hızlı kayıt, bildirimler.

## Verilen kararlar

| Tarih | Konu | Karar |
| :-- | :-- | :-- |
| 2026-11-16 | Depo | Herkese açık GitHub deposu (açık kaynak). `main` korumalı: doğrudan push ve force push yok, her değişiklik dal + PR ile gelir. CI sır taraması yapar. |
| 2026-11-16 | Lisans | Kod MIT. Karakter, görseller ve ses efektleri (`assets/`, `tasarim-kaynak/`) CC BY 4.0. |
| 2026-11-16 | Dağıtım | Hazır paket dağıtılmaz, noter onayı yok. Herkes depoyu klonlayıp kendi Apple geliştirici kimliğiyle derler ve kendi anahtarlarını girer. Kişiye özel ayarlar (ekip kimliği, paket kimliği) depoya girmeyen yerel bir yapılandırma dosyasında durur. |
| 2026-11-16 | Kişisel veri | Depoda gerçek kullanıcıya ait bilgi yok. Belgeler ve örnek veri uydurma örnek kullanıcı "Ada" üzerinden anlatılır. |
| 2026-11-16 | Dil | Belgeler, arayüz ve README Türkçe. Kod, tanımlayıcılar ve commit mesajları İngilizce. |
| 2026-11-16 | Ruh halleri | Yedi ruh hali (uykulu dahil). |
| 2026-11-16 | Çağırma kısayolu | Varsayılan ⌘ ⌘ (Girdi İzleme izniyle). Kullanıcı ayarlardan ek bir kısayol kaydedebilir (`KeyboardShortcuts` paketi). |
| 2026-11-16 | "Efendim?" süresi | 250 ms bütçesi ilk ses için: `uyan` efekti. "Efendim?" efekt bittikten 60 ms sonra çalar, ikisi üst üste binmez. |
| 2026-11-16 | Uyandırma kelimesi | Önce sherpa-onnx anahtar kelime tespiti ("optic" anahtarı, eğitimsiz) denenir. Ölçümü geçemezse kendi eğittiğimiz küçük model. Porcupine elendi (Türkçe yok, ücretsiz katman kapandı). |
| 2026-11-16 | Optik'in sesi | Kör dinleme testinde ElevenLabs'in hazır sesi **Jessica** seçildi. Sabit cümleler Jessica ile üretilip pakete girer, canlı yanıtlar `eleven_v4_turbo` ile akışla gelir. Kullanıcı ayarlardan kendi ElevenLabs sesini girebilir; o zaman sabit cümleler onun Mac'inde yeniden üretilir. |
| 2026-11-16 | Sabit cümlelerin lisansı | Jessica ile ElevenLabs ücretsiz planında üretildi, `assets/sesler/konusma/` altında. CC BY 4.0 dışında: yalnızca ticari olmayan kullanım, ElevenLabs atfıyla (`LICENSE-ASSETS`, `konusma/OKU.txt`). Optik ticari bir ürün olursa ücretli planla yeniden üretilir. |
| 2026-11-16 | Kapalı adacık | 312 × 38 pt kalır (çentikten 6 pt aşağı taşar). Renk `#000000`; LCD ekranda kamera kutusundan biraz açık görünmesi ekranın arka ışığından. |
| 2026-11-16 | En düşük macOS | macOS 15. Uyandırma kelimesi için kullanılacak `speech-swift` macOS 15 istiyor. Optik zaten Apple Silicon şartı koyuyor ve bütün Apple Silicon Mac'ler macOS 15'e güncellenebildiği için kimse dışarıda kalmıyor. |

## Açık sorular

Bunlara dayanan bir iş yapmadan önce kullanıcıya sor.

1. **Telefon:** iPhone mu, Android mi, ikisi de mi? (iPhone ise SwiftUI ile kod paylaşılır, Android varsa Expo / React Native mantıklı.)
2. **Uyandırma kelimesi:** "optic" anahtarıyla anahtar kelime tespiti Türkçe söyleyişte yeterince güvenilir mi? Ölçümden sonra kesinleşir.
3. **Takvim kaynağı:** Apple Takvim mi, Google Takvim mi? Tek yönlü okuma mı, iki yönlü mü?
4. **Mevcut bütçe verisi:** kullanıcının başka bir bütçe uygulamasındaki harcamaları Optik'e bir kez mi aktarılacak (CSV), yoksa Optik oradan mı okuyacak?
5. **Ödeme planı şablonları:** varsayılan %40 / %30 / %30 doğru mu, iş türüne göre değişiyor mu?
6. **Para birimi:** yalnızca TL mi, döviz teklifleri var mı?
7. **Brifing saatleri:** 08.30 ve 21.30 uygun mu?
