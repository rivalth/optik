# Optik'in ses kimliği

Optik'in varsayılan sesi **Jessica**: ElevenLabs'in hazır seslerinden biri (`cgSgspJ2msm6clMCkdW9`). Kör dinleme testinde seçildi (2026-11-16). Ses efektleri (cıvıltılar, kabuk vuruşu) ayrıdır ve hazırdır: `assets/sesler/`.

| | Model | Not |
| :-- | :-- | :-- |
| Sabit cümleler | `eleven_v4` | Bir kez üretilir, pakete girer |
| Canlı yanıtlar | `eleven_v4_turbo`, akış | Ölçülen ilk ses 260–530 ms |

İstek gövdesinde `language_code: "tr"` gönderilir.

## Aranan ses

Varsayılan ses seçildi. Bu tarif kişiye özel ses tasarlayan kullanıcı ve ileride yapılacak yeni bir seçim içindir.

- Genç, parlak, küçük bir karaktere yakışan bir ses. Çizgi film sesi kadar abartılı değil, gün boyu dinlenince yormayacak kadar doğal.
- Perde ortalamanın biraz üstünde. Tını temiz, nefesli ya da boğuk değil.
- Hız orta-hızlı. Cümle sonları net biter, uzatmaz.
- Ton: neşeli, meraklı, kendinden emin. Uyarı verirken bile telaşlı değil.
- Türkçe ana dili gibi. Sayılar, saatler ve özel isimler düzgün okunmalı.
- Cinsiyeti belirgin olmayan ya da hafif çocuksu bir ses tercih edilir.

## Seçim yöntemi

1. Adaylar ElevenLabs ve Cartesia'dan gelir. Her serviste "ses tasarımı" (ya da hazır ses kütüphanesi) ile en fazla üç aday seç ya da üret. Tarif olarak yukarıdaki maddeleri kullan. ElevenLabs ücretsiz planında API yalnızca hazır sesleri ve hesabın kendi seslerini kullanır; ses tasarımı web arayüzünden yapılır.
2. Her adaya şu beş cümleyi okut:
   - "Efendim?"
   - "Tamam, kaydettim."
   - "Yarın saat üçte Yeliz'le buluşman var, on dakika önce hatırlatayım mı?"
   - "Kuzey Mobilya için on sekiz bin lira aldım. Kalan on sekiz bin."
   - "Elektrik faturası için yarın son gün."
3. Kullanıcı adayları servis adı gizli olarak (kör) dinler ve birini seçer. Seçilen servis ve ses kimliği ayarlarda saklanır.
4. `llm/sabit-cumleler.json` içindeki cümleler bu sesle üretilir, `assets/sesler/konusma/<id>.wav` olarak kaydedilir (44,1 kHz, 16 bit, mono). Yüksek kaliteli model kullan, gecikme burada önemli değil. Ücretsiz planda 44,1 kHz PCM yok: MP3 (44,1 kHz, 128 kbps) alınır, WAV'a çevrilir. Baştaki sessizlik 10 ms'ye kırpılır (gecikmeye eklenmesin), sonda 80 ms kalır, konuşmanın RMS düzeyi -20 dBFS'e eşitlenir (tepe en fazla -3 dBFS). Atıf ve lisans: `assets/sesler/konusma/OKU.txt`.
5. Canlı yanıtlar aynı sesle, düşük gecikmeli modelle akışla üretilir.

## Kişiye özel ses

Kullanıcı Optik'e kendi sesini verebilir:

1. ElevenLabs web arayüzünde Voice Design ile tarif yukarıdaki maddelerden yazılarak bir ses tasarlanır ya da Instant Voice Clone ile bir ses klonlanır. Klon yalnızca sesin sahibinin açık rızasıyla yapılır; kaydı en iyisi sahibi kendisi okur.
2. Ayarlarda ses kimliği girilir. Optik beş sınama cümlesini bu sesle okutur, kullanıcı onaylar.
3. `llm/sabit-cumleler.json` bu sesle yeniden üretilir ve `~/Library/Application Support/Optik/konusma/<id>.wav` altına yazılır. Paketteki Jessica cümlelerinin yerine bunlar çalar.
4. Ses kimliği ve üretilen dosyalar depoya, günlüğe ya da hata raporuna girmez. "Varsayılana dön" yerel dosyaları siler, Jessica'ya döner.

## Okuma kuralları

- Metin sentezden önce normalleştirilir: "₺18.000" → "18.000 lira", "13.00" → "on üç", "%80" → "yüzde seksen", "3 gün" olduğu gibi.
- Bir yanıt 220 karakteri geçerse yalnızca ilk iki cümle okunur, gerisi adacıkta gösterilir.
- Ses efekti önce, konuşma 60 ms sonra.

## Yedek

Ağ yokken sistemin Türkçe sesi kullanılır. Karakter sesi değildir, bunu kullanıcı ayarlardan kapatabilir (o zaman yalnızca ses efekti ve yazı).
