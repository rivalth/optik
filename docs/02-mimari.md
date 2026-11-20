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
- Göstergeler: kapalı adacık, Mac'te bir şey değişince kanatlarında bir anlığına gösterir: ses düzeyi, parlaklık ve klavye ışığı (tuşla değişince), mikrofonun sessize alınması, şarj ve düşük pil, kablosuz kulaklık, pano, ekran görüntüsü, yeni şarkı, klavye dili. Her biri Ayarlar → Göstergeler'den açılıp kapanır, kapalı olan hiç dinlenmez. Kaynaklar değişim bildirimidir (Core Audio, IOKit güç kaynağı, Spotify ve Müzik'in dağıtık bildirimleri, giriş kaynağı bildirimi, sistem tuşları); yalnızca pano yarım saniyede bir sayaç okur. Parlaklık ve klavye ışığının açık bir API'si yok, sistemin kendi çerçeveleri (`DisplayServices`, `CoreBrightness`) çalışma anında aranır, bulunamazsa çubuksuz gösterilir. Şifre yöneticilerinin işaretlediği pano içeriği gösterilmez. Sistemin kendi ses ve parlaklık göstergesi de görünmeye devam eder.
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

**Sonuç (2026-11-17):** 1. yol denendi ve elendi. CPU'yu bütçeye indirdik (M2'de sessiz odada %0,57), ama İngilizce model temiz sentezlenmiş kayıtlarda bile Türkçe "Optik"i kaçırdı. Paket depoya girmedi. Şimdiki uygulama 3. yolun kısılmış hâli (`WakeWordListener`): kendi `AVAudioEngine`'i (yankı giderme olmadan) dinler, odanın 12 dB üstüne 0,4 sn'lik bir boşluktan sonra yükselen bir kelime 1,25 sn'lik pencereye alınır ve yüklü Whisper modeline gider; metin "Optik" ile başlıyorsa (`WakePhrase`) ve ses profili varsa konuşan kullanıcıysa Optik uyanır. Aynı anda tek denetim çalışır, en yeni pencere sırada bekler. Ölçülen: sessiz odada CPU %0, konuşulan odada yaklaşık %13 (bütçenin üstünde, açık iş), denetim 250–780 ms, uyandırma → adacık 63 ms. Ayar varsayılan kapalı: açıkken mikrofon sürekli açık kalır ve macOS'un turuncu noktası yanar.

Yanlış tetiklemeyi azaltmak için: tetiklemeden sonra 1,5 sn içinde konuşma başlamazsa adacık sessizce kapanır ve "Efendim?" tekrar edilmez.

**Tek nefeste çağırma:** uyandırma dinleyicisi son birkaç saniyeyi bir halka tamponda tutar. "Optik" yakalandığında (kelime bittikten ~0,3–0,5 sn sonra) konuşma sürüyorsa "Efendim?" çalınmaz; konuşma algılama tampondaki sesle, kelimenin bittiği yerden başlar ve yazıya çevirmeden önce baştaki "Optik" atılır. Uyandırma dinleyicisi ile konuşma sırasındaki yankı gidermeli yakalama arasında geçiş ses kaybetmemeli. **Ölç:** "Optik"ten sonra durmadan konuşulduğunda yakalama oranı (model kelimeden sonra kısa bir boşluk bekliyor).

### 3.2 Konuşmayı yazıya çevirme

- **Birincil: WhisperKit** (Argmax, MIT). Whisper modellerini Core ML ile Apple Silicon'da çalıştırır, çok dilli. macOS 14+ ve Apple Silicon ister. Paket `argmax-oss-swift` deposundaki `WhisperKit` ürünü, 1.1.1'e sabit.
- **Model:** kullanıcı Ayarlar → Ses'ten seçer, ilk seferde Hugging Face'ten indirilir (uygulama kabının `Application Support/Optik/Models` klasörüne). M2'de ölçülen:

  | Model | Türkçe | Konuşma sonu → metin | Not |
  | :-- | :-- | :-- | :-- |
  | `openai_whisper-base` ("Hızlı") | Yetersiz | 110–390 ms | Yalnızca çok yavaş Mac'ler için |
  | `openai_whisper-small` ("Dengeli", varsayılan) | İyi | 230–380 ms | Neural Engine'de. İlk derleme ~45 sn, sonra açılışta 1,6 sn'de yüklenir |
  | `openai_whisper-large-v3-v20240930_turbo_632MB` ("En doğru") | Çok iyi | 6–9 sn (5 sn'lik cümle, GPU) | Neural Engine derlemesi saatlerce sürüp takıldı, bu yüzden GPU'da çalışır; sesli tur için fazla yavaş. Sentezlenmiş bir Türkçe cümlede `small` cümleyi bozarken turbo neredeyse kusursuz yazdı (2026-11-20) |
- Uyandırma kelimesi her sesi denetlediği için her zaman hızlı modelle çalışır: kullanıcı "En doğru"yu seçtiyse uyandırma için indirilmiş `small` (yoksa `base`) ayrıca yüklenir (`SpeechModel.forWakeWord`). Aynı yavaş modeli paylaşınca denetimler kuyruğa giriyor, uyandırma kaçıyor ve cümle 10–20 sn bekliyordu.
- Türkçeye ince ayarlı modeller (ör. `turkmedstt/whisper-large-v3-turkish-general`, Apache-2.0, kendi 320 kliplik testinde WER 0,079 ve temel `large-v3` için 0,121) tam `large-v3` tabanlı: 32 kod çözücü katmanı, 3 GB F16, Core ML sürümü yok. Turbo'dan da yavaş olacağı için sesli tur için uygun değil. Türkçeye ince ayarlı bir turbo bulunur ve Core ML'e çevrilirse yeniden değerlendir.
- NVIDIA `Nemotron-3.5-ASR-Streaming-0.6b` (OpenMDW-1.1, Türkçe "transcription-ready", FLEURS WER yaklaşık %11–12) FluidAudio'da Core ML olarak hazır, yeni bağımlılık istemez. M2'de Neural Engine'de 5 sn sesi 0,1–0,2 sn'de çevirir, model 640 MB. Ama Türkçe doğruluğu düşük ("yarın saat üçte" → "yarımsağa üçte") ve İngilizce terim karışık cümlelerde zayıf: altı cümlenin ikisinde boş sonuç, "auto" dilde Hindi harfleri, kelime ipucuyla da düzelmedi. Şimdilik kullanılmıyor. Parakeet-TDT-0.6B-v3 ve Canary-1B-v2 Türkçe içermiyor.
- **Cümleyi yazan motor** Ayarlar → Ses'ten seçilir (`SpeechEngine`, `SentenceTranscriber`). Uyandırma kelimesi ve konuşurken gösterilen canlı metin her seçenekte Whisper ile bu Mac'te kalır. Seçilen motor çalışmazsa (bağlantı, anahtar, kredi yok) cümleyi Whisper yazar.
  - **Whisper** (varsayılan), yukarıdaki model.
  - **Apple dikte** (macOS 26+, `AppleDictation`): `SpeechTranscriber`'da Türkçe yok, `DictationTranscriber` (`.shortDictation`) Türkçeyi destekliyor ve dil dosyaları sistemin diktesiyle geliyor. M2'de 5 sn'lik cümle 0,14–0,42 sn, düz Türkçede kusursuz, İngilizce terim karışık cümlelerde zayıf. İsim ve terimler `AnalysisContext` ile ipucu olarak verilir.
  - **ElevenLabs Scribe v2 Realtime** (bulut, `ScribeTranscriber`): soket Optik uyanınca açılır (bağlantı yarım saniye sürüyor). Kullanıcı konuşmaya başlayınca ses 250 ms'de bir akar (`LiveSentence`, `ScribeLiveSession`), Scribe'ın ara metni adacıkta görünür ve bitmiş komutlar ("Spotify'ı aç,") konuşma sürerken çalışır. Konuşma bitince yalnızca kalan parça commit ile gider: uygulamada konuşma sonu → metin 0,20–0,28 sn (bir ölçümde 0,77). Akış koparsa cümle tek seferde yeniden gönderilir (0,45–0,71 sn), o da olmazsa Whisper yazar. Bir cevabın üstüne konuşulursa takip sorusu da akışa geçer; "Optik, …" diye tek nefeste söylenen cümle uyandırma dinleyicisinden geldiği için tek seferde gider. Yedi test cümlesinin beşini neredeyse kusursuz yazdı: "branch'ı main'e merge", "staging'de bir bug", "Kubernetes Pod'larını", saat "15.00'te". İsim ve terimler `keyterms` ile gider (en çok 50, her biri en çok 20 harf). Fiyat 0,22 $/saat; ücretsiz planda ölçülen 5,2 sn'lik cümle başına 7 kredi, yani tur başına 8–10 kredi. Sesin Mac'ten çıktığı tek yer burası, yalnızca kullanıcı seçerse (bölüm 7). `scribe_v3_live` aynı fiyatta, ama bu testte iki cümlede v2'den kötüydü.
- **Gürültü filtresi** (`TranscriptFilter`): Whisper altyazılı videolarla eğitildiği için gürültüde "(Müzik)", "Altyazı M.K.", "İzlediğiniz için teşekkürler" yazar. Ses etiketleri silinir, yalnızca bu cümlelerden oluşan sonuç atılır, tekrar döngüsüne giren (sıkıştırma oranı 2,4 üstü) ve konuşma olmayan (`noSpeechProb` 0,4 üstü, ortalama log olasılığı -1 altı) bölümler düşer. Tek başına "Teşekkürler" yalnızca model eminse kalır.
- **İsim ipucu:** Whisper'a önceki metin olarak yalnızca "Optik, <kullanıcı adı>." verilir. Geliştirici terimlerinden bir cümle birkaç kelimeyi düzeltti ama turbo'nun süresini ikiye katladı (8 sn → 16 sn).
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
- Ses verisi diske yazılmaz, ağa çıkmaz. Tek istisna kullanıcının Ayarlar'da kendisi seçtiği ElevenLabs Scribe: "Optik" dedikten sonraki cümlenin sesi ElevenLabs'e gider (bölüm 3.2). Uyandırma dinlemesi ve canlı metin hiçbir zaman gönderilmez. ElevenLabs'in sıfır saklama modu yalnızca kurumsal hesaplarda var; Ayarlar bunu söylemez ama sesin gittiğini açıkça yazar. Hata ayıklama kaydı varsayılan kapalı ve ayrı bir ayarın arkasında.
- Günlüklerde kişi adı, tutar, not metni yok. Yalnızca tür ve süre.
- Optik App Sandbox içinde çalışmaz (2026-11-20 kararı): başka uygulamalarda tıklamak için Erişilebilirlik API'si gerekiyor ve Apple bunu korumalı uygulamalarda desteklemiyor. Optik App Store'a gitmiyor, her kullanıcı kendi Mac'inde kaynaktan derliyor. Hardened Runtime açık kalır. İlk açılışta eski kaptaki (`~/Library/Containers/<paket kimliği>`) ayarlar ve modeller `~/Library` altına bir kez taşınır (`ContainerMigration`).
- İstenen izinler: mikrofon, ⌘ ⌘ kısayolu için Girdi İzleme, Spotify gibi uygulamalar için Otomasyon (Apple Events), tıklamalar için Erişilebilirlik (isteğe bağlı; yalnızca kullanıcı bir uygulamada tıklama gerektiren bir komut verdiğinde ya da Ayarlar'dan istenir). Girdi İzleme verilmezse ek kısayol ve menüden çağırma yine çalışır. Aşama 4'te: Kişiler, Mail ve Mesajlar için Otomasyon, kullanıcının açtığı klasörlere erişim.
- Bilgisayarı kullanma (`llm/bilgisayar-araclari.json`): Claude ekranı Erişilebilirlik ağacından numaralı bir liste olarak okur, numarayla tıklar ve yazar, sayfa ve uygulama açar, ev klasöründe dosya bulur, klasör oluşturur, taşır ve çöpe atar (silmez). Tıklama ve yazma Erişilebilirlik ile gider; Optik'in kendi imleci (nane ok ve minik Optik) hedefe uçup tıklamayı gösterir, kullanıcının faresi yerinde kalır. Erişilebilirlikle basılamayan bir öğede gerçek fare bir anlığına oraya gidip tıklar ve geri döner. Şifre alanlarına yazılmaz. Gönder, kaydol, satın al gibi son adımlardan önce kullanıcıya sorulur (`llm/sistem-istemi.md`). Araçlar Claude Code'a uygulamanın içinde, yalnızca 127.0.0.1'den ve her açılışta yenilenen bir anahtarla erişilen bir MCP uç noktasıyla verilir (`ComputerServer`); anahtar yalnızca kullanıcının okuyabildiği bir dosyada durur. API yolu henüz bu araçları kullanmıyor.
- Uygulama komutları (`LocalCommandParser`, `LocalActionRunner`) yalnızca açma, kapatma, arama, sayfa açma ve müzik çalmadır. Yalnızca http(s) sayfaları açılır. Konuşurken yapılan komutlardan önce konuşanın kullanıcı olduğu ses profiliyle doğrulanır.
- Mesajlar ve e-posta (aşama 4, `docs/01-urun.md` bölüm 6): gönderme aracı yalnızca kullanıcının adacıkta onayladığı taslağı gönderir, LLM taslağı kendisi gönderemez. E-posta ve mesaj içeriği LLM'e veri olarak, ayrı bir blokta gider; içindeki talimatlar uygulanmaz. **Doğrula:** sandbox içinden Mail ve Mesajlar'a Apple Events ile gönderme (`com.apple.security.automation.apple-events` ve hedef uygulama yetkileri), WhatsApp için `NSSharingService` ile dosya ve metin hazırlama, Spotlight'ta (`NSMetadataQuery`) sandbox sınırları.
- LLM'e giden her istekte hangi verinin gittiği `conversation_log` içinde görülebilir.

## 8. Bağımlılıklar

| Paket | Ne için | Durum |
| :-- | :-- | :-- |
| GRDB.swift | SQLite | Kullan |
| WhisperKit (`argmax-oss-swift`, MIT) | Cihazda yazıya çevirme | Kullanılıyor, 1.1.1'e sabit |
| sherpa-onnx KWS (`speech-swift` ile) | Uyandırma kelimesi | Denendi, elendi (2026-11-17): Türkçe "Optik"i yakalamadı (bölüm 3.1) |
| Anthropic API | LLM | Resmî Swift SDK yoksa `URLSession` ile doğrudan, SSE akışı |
| ElevenLabs istemcisi | Optik'in sesi; kullanıcı seçerse cümleyi yazıya çevirme (Scribe) | Paket yok, `URLSession` / `URLSessionWebSocketTask` ile doğrudan |
| KeyboardShortcuts (sindresorhus, MIT) | Kullanıcının kaydettiği ek kısayol, açıkken `Esc` | Kullanılıyor, 3.1.0'a sabit |
| FluidAudio (Apache-2.0) | Konuşanı tanıma (CAM++ ses parmak izi) | Kullanılıyor, 0.18.3'e sabit (onaylandı) |

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
