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

- Mikrofon izni, 16 kHz yakalama, VAD.
- `Transcriber` (WhisperKit), kısmi metin adacıkta.
- `LLMClient` (Claude, akış), araçsız kısa sohbet.
- `SpeechSynthesizer`: sabit cümleler dosyadan, değişken yanıt akışla. Önbellek.
- `WakeWordDetector`: önce doğrulama (bkz. mimari 3.1), sonra bağlama.
- Gecikme ölçümü ve kaydı.

**Kabul:** "Optik" → "Efendim?" 250 ms altı. "Saat kaç?" gibi bir soruda konuşma sonu → ilk ses 1,5 sn altı (10 denemenin ortancası). Optik konuşurken söz kesilince susuyor. Ağ yokken anlaşılır biçimde bildiriyor. 30 dakikalık ortam sesinde en fazla 1 yanlış tetikleme.

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

## Açık sorular

Bunlara dayanan bir iş yapmadan önce kullanıcıya sor.

1. **Telefon:** iPhone mu, Android mi, ikisi de mi? (iPhone ise SwiftUI ile kod paylaşılır, Android varsa Expo / React Native mantıklı.)
2. **Optik'in sesi:** hangi konuşma sentezi servisi ve hangi ses? Kullanıcı birkaç aday ses dinleyip seçecek (`llm/ses-kimligi.md`).
3. **Uyandırma kelimesi:** Porcupine Türkçe "Optik" kelimesini güvenilir tanıyor mu? Tanımıyorsa hangi yedek?
4. **Takvim kaynağı:** Apple Takvim mi, Google Takvim mi? Tek yönlü okuma mı, iki yönlü mü?
5. **Mevcut bütçe verisi:** kullanıcının başka bir bütçe uygulamasındaki harcamaları Optik'e bir kez mi aktarılacak (CSV), yoksa Optik oradan mı okuyacak?
6. **Ödeme planı şablonları:** varsayılan %40 / %30 / %30 doğru mu, iş türüne göre değişiyor mu?
7. **Para birimi:** yalnızca TL mi, döviz teklifleri var mı?
8. **Brifing saatleri:** 08.30 ve 21.30 uygun mu?
