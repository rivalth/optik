# Mimari

Bu doküman 16 Kasım 2026 tarihli araştırmaya dayanır. "Doğrula" yazan her madde, koda başlamadan önce kontrol edilmesi gereken bir varsayımdır. Kaynaklar en altta.

## 1. Genel yapı

```
Optik.app (macOS 15+, Apple Silicon)
├── App            giriş, menü çubuğu ajanı, ayarlar
├── Island         çentik NSPanel'i, adacık durum makinesi, kümes
├── Character      Optik çizimi (SwiftUI Shape), ruh halleri, ses efektleri
├── Voice          WakeWordDetector, VAD, Transcriber, SpeechSynthesizer
├── Brain          LLMClient, araç yürütücü, bağlam kurucu, istem
├── Proactive      kural motoru, zamanlayıcı, brifing, rapor
├── Store          GRDB, göçler, sorgular, FTS5
└── Screens        ikinci beyin penceresi (bölümler)

Packages/OptikCore   platformdan bağımsız: modeller, kurallar, para ve tarih yardımcıları, araç şemaları
```

`OptikCore` hiçbir Apple arayüz çerçevesine bağlı olmaz. İleride mobil eşlikçi aynı paketi (ya da aynı şemayı) kullanır.

## 2. Çentik adacığı

- Kenarlıksız, saydam, etkinleşmeyen bir `NSPanel`. Menü çubuğunun üstünde bir pencere düzeyinde durur, bütün masaüstlerinde görünür (`canJoinAllSpaces`, `stationary`).
- Çentik ölçüsü `NSScreen.safeAreaInsets` ve `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` ile hesaplanır. Sabit sayı yazma.
- Adacık kapalıyken panel fare olaylarını yalnızca adacık şeklinin içinde yakalar, geri kalanı alttaki pencereye geçer.
- İçerik SwiftUI. Boyut geçişleri yaylı animasyon (yaklaşık 0,45 sn, hafif taşma).
- Hazır kütüphane seçeneği: `DynamicNotchKit` (MIT, SwiftUI içeriğini çentikten gösterir). Kümes ve karakter özel çizim istediği için öneri: kendi `NSPanel` alt sınıfını yaz, `DynamicNotchKit` ve benzeri açık kaynak çentik uygulamalarını yalnızca referans olarak oku.
- Çok ekran: adacık yerleşik ekranda durur. Kapak kapalıyken dış ekranın üst ortasında yüzen hap olarak çizilir.
- Kapalıyken panel adacığın tam boyundadır. Açılırken önce panel büyür (yay taşması için kenarlarda 32 pt pay), adacık içinde yaylanır; kapanınca yay bitince panel geri küçülür.
- Tam ekran: başka bir uygulamanın penceresi ekranın tamamını (menü çubuğu dahil) kaplıyorsa kapalı adacık gizlenir, haberler bekler. Kontrol yalnızca masaüstü ve uygulama değişiminde yapılır, zamanlayıcı yok. Pencere sınırlarını okumak izin istemez.

### 2.1 Çağırma kısayolu

- Varsayılan: ⌘ ⌘ (Command tuşuna art arda iki kez basmak). Yalnızca dinleyen bir olay musluğu (`CGEventTap`, `listenOnly`) ile yakalanır, bunun için **Girdi İzleme** izni gerekir. Musluk yalnızca Command tuşunun kodunu ve değiştirici bayraklarını okur; başka bir tuşa basıldığında yalnızca "başka bir tuş" olduğunu not eder, hangi tuş olduğunu okumaz. Algılama ikinci basışta tetikler, bekleme yok.
- Ek kısayol: kullanıcı ayarlardan istediği tuş birleşimini kaydedebilir (`KeyboardShortcuts`). Varsayılanı boş.
- `Esc` yalnızca adacık açıkken yakalanır, kapalıyken başka uygulamalardan çalınmaz.
- İzin uygulamanın imzasına bağlıdır. Yalnızca bu Mac'e özel imzayla (`-`) her derlemede kimlik değişir ve izin düşer; kalıcı olması için `Config/Local.xcconfig` ile kendi geliştirici sertifikanla imzala.

## 3. Ses hattı

```
mikrofon (16 kHz mono)
  → WakeWordDetector   sürekli, cihazda            "Optik"
  → [adacık açılır, "Efendim?" sabit ses dosyası çalar]
  → VAD                konuşma başı ve sonu
  → Transcriber        akışla, cihazda, Türkçe     kısmi metin adacıkta görünür
  → Brain (LLM)        akışla, araç çağrılarıyla
  → SpeechSynthesizer  akışla, Optik'in sesi       ilk cümle hazır olunca çalmaya başlar
```

### 3.1 Uyandırma kelimesi

Dört protokol uygulaması, bu sırayla denenir:

1. **Açık sözcük dağarcıklı anahtar kelime tespiti** (sherpa-onnx KWS Zipformer, Swift sarmalayıcısı `speech-swift`). Eğitim gerekmez: anahtar kelime metin olarak verilir. Türkçe model yok; "Optik" İngilizce "optic" ile neredeyse aynı okunduğu için İngilizce model "optic" anahtarıyla denenir. **Ölç:** boşta CPU (%2 bütçesi), 30 dakika ortam sesinde yanlış tetikleme, Türkçe söyleyişte yakalama oranı.
2. **Kendi eğittiğimiz küçük model** (openWakeWord tarzı, binlerce sentezlenmiş "Optik" söyleyişiyle eğitilir, ONNX). 1. ölçümü geçemezse.
3. **Sürekli küçük model yazıya çevirme + metinde "optik" arama.** Güvenilir ama boşta CPU bütçesini zorlar. Yalnızca geçici çözüm.
4. **Klavye kısayolu (⌘ ⌘).** Her zaman çalışır, diğerleri kapalıyken tek yol.

Picovoice Porcupine elendi: Türkçe modeli yok ve ücretsiz katmanı 30 Haziran 2026'da kapandı. Açık kaynak bir projede herkesten ücretli lisans istenemez.

Yanlış tetiklemeyi azaltmak için: tetiklemeden sonra 1,5 sn içinde konuşma başlamazsa adacık sessizce kapanır ve "Efendim?" tekrar edilmez.

### 3.2 Konuşmayı yazıya çevirme

- **Birincil: WhisperKit** (Argmax, MIT). Whisper modellerini Core ML ile Apple Silicon'da çalıştırır, çok dilli. macOS 14+ ve Apple Silicon ister. Paket `argmax-oss-swift` deposundaki `WhisperKit` ürünü, 1.1.1'e sabit.
- **Model:** kullanıcı Ayarlar → Ses'ten seçer, ilk seferde Hugging Face'ten indirilir (uygulama kabının `Application Support/Optik/Models` klasörüne). M2'de ölçülen:

  | Model | Türkçe | Konuşma sonu → metin | Not |
  | :-- | :-- | :-- | :-- |
  | `openai_whisper-base` ("Hızlı") | Yetersiz | 110–390 ms | Yalnızca çok yavaş Mac'ler için |
  | `openai_whisper-small` ("Dengeli", varsayılan) | İyi | 230–380 ms | Neural Engine'de. İlk derleme ~45 sn, sonra açılışta 1,6 sn'de yüklenir |
  | `openai_whisper-large-v3-v20240930_turbo_632MB` ("En doğru") | Denenemedi | 20 sn ve üstü | Neural Engine derlemesi saatlerce sürüp takıldı, bu yüzden GPU'da çalışır; M2 GPU'da sesli tur için fazla yavaş |
- **İkincil: Apple `SpeechAnalyzer` / `SpeechTranscriber`** (macOS 26+). Çalışma anında `SpeechTranscriber.supportedLocale(equivalentTo:)` ile `tr_TR` desteğini sor. İlk çıktığında desteklenen diller arasında Türkçe yoktu. Destek varsa ve ölçümde daha hızlıysa kullan.
- Model açılışta, indirme bitince ve kullanıcı model değiştirince hemen yüklenir; Ayarlar o sırada "Hazırlanıyor…" gösterir. Derlenmiş model az yer tuttuğu için bellekte kalır (`small` yüklüyken uygulamanın bellek ayak izi 75 MB) ve yalnızca sistem belleği daralınca atılır. İlk denemede model 90 sn sonra atılıyordu; yeniden yükleme sesli turu bekletiyordu.
- Yine de beklemek gerekirse (model henüz derleniyorsa) Optik 1,5 sn sonra "Bir saniye, hazırlanıyorum." der, susup beklemez.
- Kullanıcı konuşurken 0,9 sn'de bir kısmi metin üretilip adacıkta gösterilir.
- Özel isimler (müşteri, kişi, ders adları) LLM istemine "bilinen isimler" olarak verilir, yazım hatalarını LLM düzeltir.

### 3.3 LLM

Claude API, Messages uç noktası, akışla.

| İş | Model | Neden |
| :-- | :-- | :-- |
| Tek cümleyle kayıt, kısa soru-yanıt, öneri cümlesi kurma | `claude-haiku-5-5` | En hızlı. Sınıflandırma, çıkarım ve yönlendirme işleri için |
| Brifing, haftalık rapor, planlama, hafıza araması yanıtı, fiş okuma | `claude-sonnet-5-5` | Hız ve zekâ dengesi |

- Model adları tek bir yapılandırma dosyasında durur, koda gömülmez.
- **Araçlar:** `llm/araclar.json`. LLM veriyi yalnızca bu araçlarla okur ve yazar. Yürütücü her çağrıyı şemaya göre doğrular, sonra `Store` üzerinde çalıştırır.
- **İstem önbelleği:** sistem istemi ve araç tanımları her turda aynıdır, önbelleğe alınır. Değişken kısım (şimdiki zaman, günün özeti, bilinen isimler) en sona eklenir.
- **Bağlam:** veritabanının tamamı gönderilmez. Bağlam kurucu her tur için küçük bir özet üretir: şimdiki tarih ve saat, bugünün ajandası, açık siparişlerin başlık ve müşteri listesi, bütçe kategorileri, son 5 konuşma turu. Gerisini LLM araçla ister.
- **Sesli yanıt kuralı:** yanıt en fazla iki kısa cümle. Liste gerekiyorsa adacıkta gösterilir, sesle yalnızca özeti söylenir.
- **Akış ve ses:** LLM çıktısı cümle sınırında bölünür, ilk cümle tamamlanır tamamlanmaz konuşma sentezine gönderilir.
- **Hata:** ağ yoksa Optik "İnternet yok, bunu not aldım" der, cümleyi kuyruğa yazar, bağlantı gelince işler. (Aşama 2'de yalnızca bildirir; kuyruk veritabanıyla birlikte aşama 3'te.)
- **Anahtarsız deneme:** Claude anahtarı girilmemişse Optik duyduğunu tekrar eder ("Şunu duydum: …"). Mikrofon, yazıya çevirme, ses ve gecikme anahtar olmadan uçtan uca denenebilir.
- İstek ham HTTP ile gider (`anthropic-version: 2026-10-21`). Sesli turda `thinking` kapalı ve `effort: low`; sistem istemi `cache_control` ile önbellekte, turun değişken bağlamı ayrı bir blokta.

### 3.4 Optik'in sesi

Optik'in tek, tutarlı, kendine ait bir sesi vardır. Ses kimliği tarifi `llm/ses-kimligi.md` içinde.

- **Sabit cümleler** (`llm/sabit-cumleler.json`): "Efendim?", "Tamam, kaydettim." gibi sık kullanılanlar seçilen sesle bir kez üretilir, `assets/sesler/konusma/` altına konur ve gecikmesiz çalınır. 250 ms hedefini tutturan şey budur.
- **Değişken yanıtlar:** ElevenLabs, akışla. Kör dinleme testinde (9 aday: ElevenLabs hazır ve tasarlanmış sesler, Cartesia Sonic 3.5) seçilen ses **Jessica** (ElevenLabs hazır sesi, `cgSgspJ2msm6clMCkdW9`).
  - Canlı yanıt `eleven_v4_turbo` ile, `language_code: tr`. Ölçülen ilk ses 260–530 ms (her istekte yeni TLS bağlantısıyla; açık bağlantı ve WebSocket ile daha düşük). Bütçe sıkışırsa `eleven_flash_v2_5` denenir.
  - Sabit cümleler kalite modeli `eleven_v4` ile üretilir; gecikme orada önemsiz.
  - Hazır sesler ücretsiz planda da API'den kullanılabilir. Kütüphane sesleri ve API'den ses tasarımı ücretli plan ister; arayüzde tasarlanan ya da klonlanan ses ise hesabın kendi sesidir, API'den kullanılır.
  - Sağlayıcı `SpeechSynthesizer` protokolünün arkasında durur, sonradan değiştirilebilir. Cartesia yedek aday olarak kalır (Sonic 3.5, ölçülen ilk ses ~240 ms).
- **Kişiye özel ses:** kullanıcı ayarlardan kendi ElevenLabs ses kimliğini (arayüzde tasarladığı ya da rızayla klonladığı ses) girebilir. O zaman sabit cümleler bu sesle kullanıcının Mac'inde yeniden üretilir, `~/Library/Application Support/Optik/konusma/` altına yazılır ve paketteki Jessica cümlelerinin yerine çalar. Bu dosyalar ve ses kimliği depoya girmez. "Varsayılana dön" Jessica'ya geri alır.
- **Yedek:** ağ ya da ElevenLabs anahtarı yoksa sabit cümleler paketten çalmaya devam eder, değişken yanıtlar `AVSpeechSynthesizer` Türkçe sesiyle okunur. Kurulu en iyi Türkçe ses seçilir (varsa "Yelda (Gelişmiş)"); sıkıştırılmış ses çok kötü duyulur. Karakter sesiyle aynı değildir, yalnızca yedektir. Hata mesajları da Optik'in sesiyle okunur, yedek ses yalnızca ElevenLabs'e ulaşılamazsa devreye girer.
- Sentezlenen her cümle metnine göre diskte önbelleğe alınır, aynı cümle ikinci kez ücretsiz ve anında çalar.
- Ses efektleri (`assets/sesler/*.wav`) konuşmadan ayrıdır ve her zaman yereldir.

### 3.5 Kesme ve sıra

- Optik konuşurken kullanıcı konuşmaya başlarsa (VAD) Optik susar ve dinler. Yanıtın ilk 0,6 sn'sinde kesilmez (yankı giderici o sırada oturuyor). Kesmek için kullanıcının 0,35 sn içinde en az 0,25 sn odanın belirgin üstünde konuşması gerekir; oda sesi ve kalan yankı kesmez. Yankı giderme kapalıysa kesme yoktur.
- "Tamam", "sus", "boş ver" yerelde tanınır, LLM'e gitmeden işlenir.

### 3.6 Mikrofon ve konuşma algılama

- **Yakalama:** `AVAudioEngine`, sistemin ses işlemesi (voice processing) açık: yankı giderme sayesinde Optik kendi sesini duymaz. Ses işleme, çıkış tarafının mikrofonla aynı örnekleme hızında olmasını ister (dahili mikrofon 48 kHz, hoparlör 44,1 kHz olabilir; farklıysa -10875 hatası). Ana karıştırıcı çıkışa mikrofonun hızıyla bağlanır. Ses işleme yine de açılmazsa motor onsuz çalışır.
- Ses işlemenin otomatik kazancı kapalı: cümle aralarında odayı konuşma düzeyine çıkarıyordu.
- Yakalanan ses 16 kHz mono'ya çevrilir, 20 ms'lik çerçevelerle konuşma algılayıcıya (`EndpointDetector`, OptikCore) gider.
- **Gürültü tabanı:** son 2 sn'nin en sessiz anı. Oda sesi artınca taban da yükselir; konuşmadaki kelime araları tabanı odaya yakın tutar.
- **Arka plan:** başka bir cihazda oynayan video ya da odadaki sohbet de konuşmadır. Kullanıcı konuşmadan önceki ~4 sn'nin yüksek ucu (90. yüzdelik) arka plan sayılır. Konuşmanın başlaması için arka planın 6 dB üstüne çıkmak gerekir, arka plan düzeyine dönmek cümleyi bitirir. Mikrofona yakın olan kullanıcı genelde 15–40 dB öndedir.
- Konuşma 0,12 sn eşiğin üstünde kalınca başlar. 0,7 sn tabana ya da arka plana yakın kalınca, ya da kendi en yüksek düzeyinin 20 dB altına inince biter. En fazla 30 sn sürer. Başlangıçtan önceki 0,3 sn de kayda eklenir, ilk hece kesilmez.
- Mikrofon yalnızca Optik çağrıldığında açılır ve dönüş sonu sessizliğinden (8 sn) sonra kapanır. Açıkken adacıkta yeşil nokta görünür. Mikrofon açıkken `dinliyor` efekti çalınmaz.

## 4. Veri

- SQLite, GRDB ile. Şema `veri/sema.sql`. Göçler numaralı ve geri alınamaz, her göçün testi var.
- Para alanları `INTEGER` kuruş. Tarihler UTC ISO 8601 metin.
- `notes_fts` (FTS5) notları, kişi notlarını, sipariş açıklamalarını indeksler. Türkçe için `unicode61 remove_diacritics 2` belirteçleyici.
- Her yazma işlemi `change_log` tablosuna da düşer (ne, ne zaman, hangi kaynak: ses, elle, kural). Geri alma ve ileride senkron bunu kullanır.
- Veritabanı dosyası `Application Support/Optik/` altında. Günlük otomatik yedek (son 14 gün).
- **Kilit:** Para ve İlişki tabloları kilitliyken bağlam kurucu bu tablolara dokunmaz.

## 5. Proaktif motor

- Kurallar `OptikCore` içinde saf fonksiyonlardır: veri anlık görüntüsünü alır, öneri ve hatırlatıcı listesi döndürür. LLM'siz test edilir.
- Zamanlayıcı dakikada bir değil, bir sonraki olayın zamanına göre uyanır.
- LLM yalnızca cümle kurmak için çağrılır, sonuç önbelleğe alınır. LLM erişilemezse şablon cümle kullanılır.
- Haber verme önceliği: vadesi gelen tahsilat ve 15 dakika içindeki etkinlik hemen çıkar. Diğerleri kullanıcı klavye ve fareyle meşgulken bekler, 20 sn boşlukta çıkar.

## 6. Performans tasarımı

Bütçeler `CLAUDE.md` içinde. Nasıl tutturulur:

| Bütçe | Yöntem |
| :-- | :-- |
| Uyandırma → adacık 100 ms | Panel hep hazır ve gizli, yalnızca animasyon başlar. |
| Uyandırma → ilk ses 250 ms | `uyan` efekti önceden çözülmüş `AVAudioPlayerNode` tamponunda, birkaç ms içinde başlar. "Efendim?" efekt bittikten 60 ms sonra gelir (ses ve efekt üst üste binmez). |
| Konuşma sonu → ilk ses 1,5 sn | Akışla yazıya çevirme (son kısım yaklaşık 300 ms) + Haiku ilk cümle + akışla sentez. Bağlantılar (LLM ve sentez) uyandırma anında açılır. |
| Boşta CPU %2 | Yalnızca uyandırma kelimesi motoru çalışır. Animasyonlar adacık kapalıyken durur (yeşil nokta hariç, o da Core Animation'da). |
| Boşta bellek 150 MB | Yazıya çevirme modeli kullanılmadığında bellekten atılır. |
| Kare hızı | Karakter katmanları `CAShapeLayer` / SwiftUI `Canvas`, dönüşüm animasyonları GPU'da. Her karede düzen hesabı yok. |

Her ses turunda şu süreler ölçülür ve kaydedilir: `wake_to_island`, `wake_to_efendim`, `speech_end_to_transcript`, `transcript_to_first_token`, `first_token_to_first_audio`, `total`. Veritabanı gelene kadar (aşama 3) sistem günlüğüne `latency` kategorisiyle JSON olarak yazılır; sonra `conversation_log.latency_ms_json` alanına:

```bash
log show --last 10m --info --predicate 'subsystem == "io.github.rivalth.optik" AND category == "latency"'
```

## 7. Güvenlik ve gizlilik

- Anahtarlar (Claude, konuşma sentezi, uyandırma kelimesi) Keychain'de. İlk açılışta ayarlar ekranından girilir.
- Ses verisi diske yazılmaz, ağa çıkmaz. Hata ayıklama kaydı varsayılan kapalı ve ayrı bir ayarın arkasında.
- Günlüklerde kişi adı, tutar, not metni yok. Yalnızca tür ve süre.
- Erişilebilirlik izni gerekmiyor. İstenen izinler: mikrofon (aşama 2) ve ⌘ ⌘ kısayolu için Girdi İzleme. Girdi İzleme verilmezse ek kısayol ve menüden çağırma yine çalışır.
- LLM'e giden her istekte hangi verinin gittiği `conversation_log` içinde görülebilir.

## 8. Bağımlılıklar

| Paket | Ne için | Durum |
| :-- | :-- | :-- |
| GRDB.swift | SQLite | Kullan |
| WhisperKit (`argmax-oss-swift`, MIT) | Cihazda yazıya çevirme | Kullanılıyor, 1.1.1'e sabit |
| sherpa-onnx KWS (`speech-swift` ile) | Uyandırma kelimesi | Denenecek (onaylandı); ölçümü geçerse kalır |
| Anthropic API | LLM | Resmî Swift SDK yoksa `URLSession` ile doğrudan, SSE akışı |
| ElevenLabs istemcisi | Optik'in sesi | Paket yok, `URLSession` / `URLSessionWebSocketTask` ile doğrudan |
| KeyboardShortcuts (sindresorhus, MIT) | Kullanıcının kaydettiği ek kısayol, açıkken `Esc` | Kullanılıyor, 3.1.0'a sabit |

Bunların dışında bağımlılık eklemeden önce sor.

## 9. Mobil eşlikçi (sonraki aşama)

- Mac uygulaması tek başına tam çalışır. Mobil sonradan gelir.
- Senkron için `change_log` tabanlı basit bir sunucu (örnek: Postgres üstünde barındırılan bir servis) yeterli. Çakışma kuralı: son yazan kazanır, para kayıtlarında birleştirme yapılmaz, ikisi de tutulur.
- Platform seçimi açık soru (bkz. `docs/04-yol-haritasi.md`).

## Kaynaklar

- Claude modelleri ve kimlikleri: https://platform.claude.com/docs/en/models/overview
- Claude araç kullanımı: https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview
- Claude akış: https://platform.claude.com/docs/en/build-with-claude/streaming
- Claude istem önbelleği: https://platform.claude.com/docs/en/build-with-claude/prompt-caching
- Claude Code proje talimat dosyaları: https://code.claude.com/docs/en/memory
- sherpa-onnx anahtar kelime tespiti: https://k2-fsa.github.io/sherpa/onnx/kws ve Swift sarmalayıcısı https://github.com/soniqo/speech-swift
- Picovoice ücretsiz katmanının kapanışı: https://community.home-assistant.io/t/fyi-picovoice-confirmed-free-tier-accesskeys-will-stop-working-after-june-30-2026/1012744
- WhisperKit: https://github.com/argmaxinc/WhisperKit ve https://arxiv.org/html/2507.10860v1
- Apple SpeechAnalyzer: https://developer.apple.com/documentation/speech/speechanalyzer
- SpeechAnalyzer dil desteği özeti: https://blog.addpipe.com/apple-speechanalyzer-api/
- ElevenLabs gecikme rehberi: https://elevenlabs.io/docs/eleven-api/guides/how-to/best-practices/latency-optimization
- DynamicNotchKit: https://github.com/MrKai77/DynamicNotchKit
