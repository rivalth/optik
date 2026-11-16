# Optik

Optik, tek bir kullanıcı için kişisel "ikinci beyin" asistanıdır. Açık kaynaktır: herkes depoyu klonlayıp kendi Mac'inde kendi asistanını kurabilir. MacBook çentiğinde bir kümeste yaşar. "Optik" diye seslenildiğinde kümesten çıkar, "Efendim?" der, Türkçe konuşmayı dinler, bir LLM ile anlar, işi yapar ve kendi sesiyle yanıt verir. Buluşmaları, kişileri, dersleri, takvimi, projeleri, harcamaları, bütçeyi, ilişkiyi ve müşteri siparişlerini tutar. Rapor, öneri ve hatırlatıcılarla kendisi haber verir.

Karakter: altı kırık bir yumurta, kırıktan civciv ayakları çıkıyor, kabuktaki çatlaktan gözleri ve gagası görünüyor.

## Önce bunları oku

Bu dosya kısa tutuldu. Bir işe başlamadan ilgili dokümanı oku:

| Ne yapıyorsan | Oku |
| :-- | :-- |
| Herhangi bir özellik, ekran, akış | `docs/01-urun.md` |
| Mimari, ses hattı, LLM, veri, performans | `docs/02-mimari.md` |
| Karakter çizimi, animasyon, ses efekti | `docs/03-karakter.md` |
| Sırada ne var, kabul kriterleri | `docs/04-yol-haritasi.md` |
| Veritabanı | `veri/sema.sql`, `veri/ornek-veri.json` |
| LLM istemi ve araçları | `llm/sistem-istemi.md`, `llm/araclar.json` |
| Görsel, ikon, ses dosyaları | `assets/README.md` |

Tasarımın çalışan referansı: `assets/animasyon/optik-demo.html` (tarayıcıda aç). Ekran tasarımlarının kaynağı: `tasarim-kaynak/`.

## Kararlaştırılmış teknik seçimler

- **Platform (1. aşama):** macOS 14+, Apple Silicon. Swift 6, SwiftUI + AppKit. Çentik adacığı kenarlıksız bir `NSPanel`. Uygulama menü çubuğu ajanı olarak çalışır, ikinci beyin ekranları ayrı bir pencerede açılır.
- **Veri:** önce yerel. SQLite (GRDB). Bütün okumalar yerelden. Arama için FTS5. Para kuruş cinsinden tamsayı tutulur.
- **Ses hattı:** uyandırma kelimesi → konuşma sonu algılama → konuşmayı yazıya çevirme → LLM → konuşma sentezi. Uyandırma ve yazıya çevirme cihaz üzerinde çalışır.
- **LLM:** Claude API. Hızlı kayıt ve kısa yanıt için `claude-haiku-5-5`, rapor, planlama ve öneri için `claude-sonnet-5-5`. Akış (streaming), araç kullanımı ve istem önbelleği açık.
- **Ses:** Optik'in kendine ait tek bir sesi var. Sabit cümleler önceden üretilip pakete konur, geri kalanı akışla sentezlenir. Sağlayıcı bir protokolün arkasında durur, değiştirilebilir.
- **Karakter:** SwiftUI `Shape` ve Core Animation ile yerel çizilir. Web görünümü, video ya da GIF kullanılmaz.

Ayrıntı, gerekçe ve doğrulanması gereken noktalar `docs/02-mimari.md` içinde.

## Çalışma kuralları

- Arayüz metinleri Türkçe. Kod, tanımlayıcılar, commit mesajları İngilizce. Kullanıcıya dönük her metin `Localizable` üzerinden gelir.
- Para: `Int` kuruş. Ekranda `₺23.000` biçimi (binlik ayırıcı nokta). Kayan nokta ile para hesabı yapma.
- Tarih: veritabanında UTC ISO 8601, ekranda `Europe/Istanbul`. Saat `13.00` biçiminde yazılır.
- Her ağ çağrısı bir protokolün arkasında (`LLMClient`, `SpeechSynthesizer`, `Transcriber`, `WakeWordDetector`). Testlerde sahtesi kullanılır.
- Ana iş parçacığında dosya, ağ, model yükleme ya da veritabanı yazması yok.
- API anahtarları yalnızca Keychain'de. Depoya, günlüğe, hata raporuna anahtar ya da ses kaydı yazma.
- LLM veriyi yalnızca `llm/araclar.json` içindeki araçlarla değiştirir. Araç çağrısı olmadan "kaydettim" denmez.
- Para kaydı, silme ve dışarıya mesaj gönderme gibi geri alınması zor işlerde Optik önce ne yaptığını söyler ve geri alma sunar.
- Karakterin görünüşünü değiştirme. Ölçüler, renkler ve ruh halleri `docs/03-karakter.md` ve `assets/` ile sabit.
- Yeni bağımlılık eklemeden önce sor. Var olan bağımlılık listesi `docs/02-mimari.md` içinde.

## Depo ve git kuralları

Depo herkese açık. Buraya giren her şey herkese yayınlanır.

- `main` korumalı. Doğrudan push ve force push yok. Her değişiklik bir dalda yapılır ve PR ile gelir.
- Dal adı: `<tür>/<kısa-ad>`, örnek `feat/notch-panel`, `docs/decisions`.
- Commit mesajları ve PR başlıkları [Conventional Commits](https://www.conventionalcommits.org/) biçiminde, İngilizce: `feat(island): add notch panel`. Türler: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`.
- Commit mesajlarında ve PR açıklamalarında Claude adı geçmez. `Co-Authored-By` satırı ya da "Generated with" notu eklenmez.
- Depoya gerçek kişisel veri girmez: gerçek isim, e-posta, telefon, tutar, ses kaydı, ekran görüntüsündeki kişisel bilgi. Örnekler uydurma kullanıcı "Ada" üzerinden yazılır.
- Anahtar, sertifika, `.p12`, `.mobileprovision`, kişiye özel ekip kimliği depoya girmez. CI her PR'da sır taraması yapar.

## Performans bütçeleri (aşılırsa iş bitmiş sayılmaz)

| Ölçüm | Hedef |
| :-- | :-- |
| Uyandırma kelimesi → adacığın açılmaya başlaması | 100 ms altı |
| Uyandırma kelimesi → ilk ses (`uyan` efekti) | 250 ms altı. "Efendim?" efekt bittikten 60 ms sonra gelir |
| Konuşma bitti → Optik'in ilk sesi | 1,5 sn altı (hedef 1 sn) |
| Boşta CPU (yalnızca uyandırma kelimesi dinlerken) | %2 altı |
| Boşta bellek | 150 MB altı |
| Animasyonlar | ekranın yenileme hızında, kare düşürmeden |
| Yerel sorgu (ekran açılışı) | 16 ms altı |
| Soğuk açılış | 1 sn altı |

Her ses turunda bu sürelerin ölçülüp `conversation_log.latency_ms_json` alanına yazılması zorunlu.

## Gizlilik

- Ses cihazdan çıkmaz. Dışarıya yalnızca yazıya çevrilmiş metin (LLM) ve seslendirilecek metin (konuşma sentezi) gider.
- Mikrofon açıkken adacıkta yeşil nokta görünür. Tek kısayolla mikrofon tamamen kapanır.
- Para ve İlişki bölümleri Touch ID ile kilitlenebilir. Kilitliyken LLM bağlamına bu veriler girmez.

## Komutlar

```bash
swift test --package-path Packages/OptikCore
xcodebuild -project Optik.xcodeproj -scheme Optik -destination 'platform=macOS,arch=arm64' build
xcodebuild -project Optik.xcodeproj -scheme Optik -destination 'platform=macOS,arch=arm64' test
```

CI (`.github/workflows/build.yml`) aynı üç adımı `macos-26` üzerinde çalıştırır.

## Proje yapısı

| Yol | Ne |
| :-- | :-- |
| `Optik.xcodeproj` | Elle yazılmış proje. Klasörler "senkron grup": `Optik/` ve `OptikTests/` altına eklenen dosya projeye kendiliğinden girer, `project.pbxproj` dosyasına dokunmak gerekmez. |
| `Optik/` | Uygulama: `App/`, `Character/` (karakter çizimi ve animasyonları), `Sound/` (ses efektleri), `Preview/` (karakter önizlemesi), `Settings/`, `Theme/`, `Resources/` (varlık kataloğu, `Localizable.xcstrings`, yazı tipleri). Ses efektleri kopyalanmaz, `assets/sesler` doğrudan hedefe bağlıdır. |
| `OptikTests/` | Uygulama testleri (Swift Testing). Uygulama içinde çalışır. |
| `Packages/OptikCore/` | Platformdan bağımsız çekirdek. AppKit, UIKit, SwiftUI içe aktarılmaz. |
| `Config/` | `Base.xcconfig` (ortak ayarlar), `Local.xcconfig.example` (kişiye özel ayar örneği), `Info.plist`, `Optik.entitlements`. |

- Tasarım tokenları `OptikCore/DesignTokens.swift` içinde. `assets/tasarim-tokenlari.json` ile farklılaşırsa `DesignTokensTests` kırılır. JSON'u değiştirirsen Swift tarafını da güncelle.
- Kişiye özel imza ayarları `Config/Local.xcconfig` dosyasında (depoya girmez). Yoksa uygulama "yalnızca bu Mac'te çalıştır" imzasıyla derlenir.
- Kullanıcı metni ekleyince `Localizable.xcstrings` içinde göründüğünü kontrol et. Kaynak dil Türkçe.
- Karakter `optik.css` ile birebir: geometri `CharacterGeometry`, anahtar kareler `CharacterAnimations` içinde, CSS'teki adlarıyla. CSS değişirse ikisini birlikte güncelle.
- Karakteri referansla karşılaştırmak için: `TEST_RUNNER_OPTIK_WRITE_SNAPSHOTS=1 xcodebuild ... test -only-testing:OptikTests/CharacterSnapshotTests`. PNG'ler `~/Library/Containers/<paket kimliği>/Data/tmp/` altına düşer.
- Önizleme penceresini açık başlatmak için uygulamayı `--show-character-preview` argümanıyla çalıştır.

## Bitti sayılması için

1. Derleniyor, testler geçiyor.
2. İlgili kabul kriterleri (`docs/04-yol-haritasi.md`) elle denenmiş.
3. Performans bütçeleri ölçülmüş, sonuç PR açıklamasında.
4. Yeni kullanıcı metinleri Türkçe ve `Localizable` içinde.
5. Karakter içeren ekranlar `assets/animasyon/optik-demo.html` ile yan yana karşılaştırılmış.

## Henüz karara bağlanmamış konular

`docs/04-yol-haritasi.md` sonundaki "Açık sorular" listesine bak. Oradaki bir konuya dayanan iş yapacaksan önce kullanıcıya sor.
