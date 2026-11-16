# Mimari

Bu doküman 16 Kasım 2026 tarihli araştırmaya dayanır. "Doğrula" yazan her madde, koda başlamadan önce kontrol edilmesi gereken bir varsayımdır. Kaynaklar en altta.

## 1. Genel yapı

```
Optik.app (macOS 14+, Apple Silicon)
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

1. **Picovoice Porcupine.** Özel uyandırma kelimesi Picovoice Console'dan saniyeler içinde eğitilir, macOS arm64 desteklenir, Swift'ten kullanılır. Erişim anahtarı gerekir. **Doğrula:** Türkçe model var mı ve "Optik" kelimesi Türkçe ya da başka bir dil modeliyle güvenilir tetikleniyor mu. Lisans koşullarını kişisel kullanım için kontrol et.
2. **Açık kaynak anahtar kelime tespiti** (örnek: sherpa-onnx keyword spotting ya da openWakeWord ile eğitilmiş özel model). Porcupine uymazsa.
3. **Sürekli küçük model yazıya çevirme + metinde "optik" arama.** Güvenilir ama boşta CPU bütçesini zorlar. Yalnızca geçici çözüm.
4. **Klavye kısayolu.** Her zaman çalışır, diğerleri kapalıyken tek yol.

Yanlış tetiklemeyi azaltmak için: tetiklemeden sonra 1,5 sn içinde konuşma başlamazsa adacık sessizce kapanır ve "Efendim?" tekrar edilmez.

### 3.2 Konuşmayı yazıya çevirme

- **Birincil: WhisperKit** (Argmax, MIT). Whisper modellerini Core ML ile Apple Silicon'da çalıştırır, akışla yazıya çevirme ve konuşma algılama içerir, çok dilli. macOS 14+ ve Apple Silicon ister. **Doğrula:** paket artık `argmax-oss-swift` deposunda bir ürün olarak geçiyor olabilir, güncel paket adını ve sürümünü kontrol et. Türkçe için model boyutunu ölçerek seç (küçük modelle başla, doğruluk yetmezse büyüt).
- **İkincil: Apple `SpeechAnalyzer` / `SpeechTranscriber`** (macOS 26+). Çalışma anında `SpeechTranscriber.supportedLocale(equivalentTo:)` ile `tr_TR` desteğini sor. İlk çıktığında desteklenen diller arasında Türkçe yoktu. Destek varsa ve ölçümde daha hızlıysa kullan.
- Model uyandırma anında yüklenir, son kullanımdan 90 sn sonra bellekten atılır (boşta bellek bütçesi için). İlk tetiklemede gecikme olmasın diye model dosyası uygulama açılışında diskten ön ısıtılır.
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
- **Hata:** ağ yoksa Optik "İnternet yok, bunu not aldım" der, cümleyi kuyruğa yazar, bağlantı gelince işler.

### 3.4 Optik'in sesi

Optik'in tek, tutarlı, kendine ait bir sesi vardır. Ses kimliği tarifi `llm/ses-kimligi.md` içinde.

- **Sabit cümleler** (`llm/sabit-cumleler.json`): "Efendim?", "Tamam, kaydettim." gibi sık kullanılanlar seçilen sesle bir kez üretilir, `assets/sesler/konusma/` altına konur ve gecikmesiz çalınır. 250 ms hedefini tutturan şey budur.
- **Değişken yanıtlar:** akışla çalışan, düşük gecikmeli, Türkçe destekleyen bir konuşma sentezi servisi. İlk aday: ElevenLabs'in düşük gecikmeli modeli (Flash v2.5, yaklaşık 75 ms model gecikmesi, 32 dil, WebSocket ile akış). **Doğrula:** güncel model listesi (daha yeni modeller çıkmış), Türkçe kalitesi, tasarlanan sesin bu modelde kullanılabildiği.
- **Yedek:** ağ yoksa `AVSpeechSynthesizer` Türkçe sesi. Karakter sesiyle aynı değildir, yalnızca yedektir.
- Sentezlenen her cümle metnine göre diskte önbelleğe alınır, aynı cümle ikinci kez ücretsiz ve anında çalar.
- Ses efektleri (`assets/sesler/*.wav`) konuşmadan ayrıdır ve her zaman yereldir.

### 3.5 Kesme ve sıra

- Optik konuşurken kullanıcı konuşmaya başlarsa (VAD) Optik susar ve dinler.
- "Tamam", "sus", "boş ver" yerelde tanınır, LLM'e gitmeden işlenir.

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
| Uyandırma → "Efendim?" 250 ms | Sabit ses dosyası önceden çözülmüş `AVAudioPlayerNode` tamponunda. |
| Konuşma sonu → ilk ses 1,5 sn | Akışla yazıya çevirme (son kısım yaklaşık 300 ms) + Haiku ilk cümle + akışla sentez. Bağlantılar (LLM ve sentez) uyandırma anında açılır. |
| Boşta CPU %2 | Yalnızca uyandırma kelimesi motoru çalışır. Animasyonlar adacık kapalıyken durur (yeşil nokta hariç, o da Core Animation'da). |
| Boşta bellek 150 MB | Yazıya çevirme modeli kullanılmadığında bellekten atılır. |
| Kare hızı | Karakter katmanları `CAShapeLayer` / SwiftUI `Canvas`, dönüşüm animasyonları GPU'da. Her karede düzen hesabı yok. |

Her ses turunda şu süreler ölçülür ve kaydedilir: `wake_to_island`, `wake_to_efendim`, `speech_end_to_transcript`, `transcript_to_first_token`, `first_token_to_first_audio`, `total`.

## 7. Güvenlik ve gizlilik

- Anahtarlar (Claude, konuşma sentezi, uyandırma kelimesi) Keychain'de. İlk açılışta ayarlar ekranından girilir.
- Ses verisi diske yazılmaz, ağa çıkmaz. Hata ayıklama kaydı varsayılan kapalı ve ayrı bir ayarın arkasında.
- Günlüklerde kişi adı, tutar, not metni yok. Yalnızca tür ve süre.
- Mikrofon izni, erişilebilirlik izni gerekmiyor. Yalnızca mikrofon istenir.
- LLM'e giden her istekte hangi verinin gittiği `conversation_log` içinde görülebilir.

## 8. Bağımlılıklar

| Paket | Ne için | Durum |
| :-- | :-- | :-- |
| GRDB.swift | SQLite | Kullan |
| WhisperKit | Cihazda yazıya çevirme | Kullan (paket adını doğrula) |
| Porcupine | Uyandırma kelimesi | Türkçe desteğini doğruladıktan sonra |
| Anthropic API | LLM | Resmî Swift SDK yoksa `URLSession` ile doğrudan, SSE akışı |
| Konuşma sentezi istemcisi | Optik'in sesi | `URLSessionWebSocketTask` ile doğrudan |

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
- Porcupine: https://github.com/Picovoice/porcupine ve https://picovoice.ai/docs/quick-start/porcupine-ios
- WhisperKit: https://github.com/argmaxinc/WhisperKit ve https://arxiv.org/html/2507.10860v1
- Apple SpeechAnalyzer: https://developer.apple.com/documentation/speech/speechanalyzer
- SpeechAnalyzer dil desteği özeti: https://blog.addpipe.com/apple-speechanalyzer-api/
- ElevenLabs gecikme rehberi: https://elevenlabs.io/docs/eleven-api/guides/how-to/best-practices/latency-optimization
- DynamicNotchKit: https://github.com/MrKai77/DynamicNotchKit
