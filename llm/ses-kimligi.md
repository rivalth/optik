# Optik'in ses kimliği

Bu pakette Optik'in konuşma sesi yok. Ses bir konuşma sentezi servisinde tasarlanıp seçilecek. Bu dosya o seçimin tarifidir. Ses efektleri (cıvıltılar, kabuk vuruşu) hazırdır: `assets/sesler/`.

## Aranan ses

- Genç, parlak, küçük bir karaktere yakışan bir ses. Çizgi film sesi kadar abartılı değil, gün boyu dinlenince yormayacak kadar doğal.
- Perde ortalamanın biraz üstünde. Tını temiz, nefesli ya da boğuk değil.
- Hız orta-hızlı. Cümle sonları net biter, uzatmaz.
- Ton: neşeli, meraklı, kendinden emin. Uyarı verirken bile telaşlı değil.
- Türkçe ana dili gibi. Sayılar, saatler ve özel isimler düzgün okunmalı.
- Cinsiyeti belirgin olmayan ya da hafif çocuksu bir ses tercih edilir.

## Seçim yöntemi

1. Seçilen serviste "ses tasarımı" ile üç aday üret. Tarif olarak yukarıdaki maddeleri kullan.
2. Her adaya şu beş cümleyi okut:
   - "Efendim?"
   - "Tamam, kaydettim."
   - "Yarın saat üçte Yeliz'le buluşman var, on dakika önce hatırlatayım mı?"
   - "Kuzey Mobilya için on sekiz bin lira aldım. Kalan on sekiz bin."
   - "Elektrik faturası için yarın son gün."
3. Kullanıcı dinleyip birini seçer. Seçilen sesin kimliği ayarlarda saklanır.
4. `llm/sabit-cumleler.json` içindeki cümleler bu sesle üretilir, `assets/sesler/konusma/<id>.wav` olarak kaydedilir (44,1 kHz, mono). Yüksek kaliteli model kullan, gecikme burada önemli değil.
5. Canlı yanıtlar aynı sesle, düşük gecikmeli modelle akışla üretilir.

## Okuma kuralları

- Metin sentezden önce normalleştirilir: "₺18.000" → "18.000 lira", "13.00" → "on üç", "%80" → "yüzde seksen", "3 gün" olduğu gibi.
- Bir yanıt 220 karakteri geçerse yalnızca ilk iki cümle okunur, gerisi adacıkta gösterilir.
- Ses efekti önce, konuşma 60 ms sonra.

## Yedek

Ağ yokken sistemin Türkçe sesi kullanılır. Karakter sesi değildir, bunu kullanıcı ayarlardan kapatabilir (o zaman yalnızca ses efekti ve yazı).
