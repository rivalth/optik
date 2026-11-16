# Ürün: Optik ne yapar

Her Optik kurulumu tek bir kullanıcıya aittir. Kullanıcının adı ayarlardan gelir (`settings.user_name`). Optik onun gününü, parasını, insanlarını ve işlerini tek yerde tutan ve kendisi haber veren bir asistandır.

Belgeler ve tasarımlar uydurma bir örnek kullanıcı üzerinden anlatılır: Ada. Küçük bir ajans işletiyor (müşteri teklifleri ve siparişleri), üniversitede okuyor (dersler, ödevler, sınavlar) ve bir ilişkisi var. Bölümler bu üç alanı kapsar.

Örnek veriler `veri/ornek-veri.json` içinde. Tasarımlardaki isimler, tutarlar ve tarihler uydurmadır.

## 1. İki yüzey

### 1.1 Çentik adacığı (her zaman açık)

MacBook çentiği siyah bir adacığa dönüşür. Sol ucunda küçük ahşap bir kümes kapısı vardır.

| Durum | Adacık | Ne olur |
| :-- | :-- | :-- |
| Bekliyor | 312 × 38 pt, alt köşeler 18 | Kapı kapalı. Sağda mikrofonun açık olduğunu gösteren yeşil nokta yavaşça yanıp söner. |
| Efendim | 460 × 150 pt, alt köşeler 40 | Kapı açılır, Optik kümesten fırlar, "Efendim?" der. Ekranda büyük "Efendim?" yazısı. |
| Dinliyor | 460 × 150 pt | Ses dalgası oynar, söylenen cümle canlı yazıya dökülür. |
| Yanıtlıyor | 480 × 214 pt | Yanıt metni görünür, Optik seslendirir. Gerekirse onay ya da geri al düğmesi. |
| Haber veriyor | 460 × 150 pt | Optik kendiliğinden çıkar: hatırlatıcı, vadesi gelen tahsilat, brifing. |

Kurallar:

- Adacık çentiğin arkasında kalan alana (ortadaki 200 × 32 pt) içerik koymaz.
- Çentiği olmayan ekranda aynı konumda yüzen bir hap olarak çizilir.
- Tıklanınca da açılır. `Esc` ya da 8 sn sessizlik kapatır.
- Tam ekran uygulamalarda ve sunum sırasında kendiliğinden çıkmaz, bildirimi biriktirir.
- Uyandırma kelimesi yanında genel bir klavye kısayolu da aynı akışı başlatır (uyandırma kelimesi çalışmasa da asistan kullanılabilsin).

### 1.2 İkinci beyin penceresi

Menü çubuğu ikonundan ya da "Optik, pencereyi aç" denince açılır. Bölümler:

| Bölüm | İçerik |
| :-- | :-- |
| Bugün | Günün akışı (ders, buluşma, teslim), tamamlanabilir maddeler, Optik'in günle ilgili cümlesi |
| Özet | Açık hatırlatıcılar ve Optik'in önerileri (kabul et / geç) |
| Takvim | Hafta şeridi, seçilen günün etkinlikleri, çakışma ve yoğunluk uyarısı |
| Kişiler | Kişi kartları: ilişki türü, son görüşme, notlar. Uzun süredir görüşülmeyenler işaretli |
| İlişki | Son birlikte geçirilen vakit, önemli günlere geri sayım, planlar, "aklında olsun" notları |
| Dersler | Haftalık program, yaklaşan ödev ve sınavlar, geri sayım |
| Projeler | Adım adım ilerleme, sıradaki adım |
| Para | Aylık bütçe, kategori sınırları, hızlı harcama ekleme, son harcamalar, nakit akışı takvimi |
| Müşteriler | Müşteri kartı: iletişim kişisi, bütün işleri, toplam ciro, notlar |
| Teklifler | Gönderilen teklifler, cevap bekleyenler, takip tarihi. Kabul edilen teklif siparişe dönüşür |
| Siparişler | Müşteri siparişleri (aşağıda ayrıntılı) |
| Rapor | Haftalık ve aylık rapor: harcama, biten iş, buluşma, öne çıkanlar, gelecek hafta için öneriler |
| Hafıza | Bütün notlarda, kişilerde, siparişlerde serbest arama |

Her bölümün üstünde Optik durur ve o bölümün durumunu tek cümleyle söyler. Ruh hali duruma göre değişir (bkz. `docs/03-karakter.md`).

## 2. Müşteri siparişi kartı

Bir sipariş şunları tutar:

- **Başlık ve müşteri.**
- **Açıklama:** işin kısa tanımı.
- **Durum:** sıradaki kilometre taşından türetilir ("Tasarım onayı aşamasında", "Teslim edildi").
- **Kilometre taşları:** sıralı, tarihli. Biten işaretli, sıradaki vurgulu. Bir kilometre taşına ödeme bağlanabilir.
- **Ödeme:** toplam, alınan, alınacak. Sıradaki tahsilatın hangi adıma bağlı olduğu. Kilometre taşı tamamlanınca bağlı ödeme "vadesi geldi" olur.
- **Masraf ve kâr:** o işe yapılan harcamalar, toplam tutardan düşülmüş hali.
- **İletişim kişisi** ve son görüşme tarihi.
- **Dosyalar:** teklif, sözleşme, fatura bağlantıları.
- **Gecikme uyarısı:** kilometre taşı tarihi 3 gün içindeyse sarı, geçtiyse turuncu.

İki ana eylem: "kilometre taşı tamam" ve "ödeme alındı". Bölüm başlığında bütün siparişlerden alınacak toplam yazar.

## 3. Teklif → sipariş → tahsilat hattı

1. Teklif oluşturulur (müşteri, başlık, tutar). Durum: taslak → gönderildi.
2. Gönderilince Optik bir takip tarihi önerir (varsayılan 3 iş günü). O gün "cevap gelmedi, yazalım mı?" diye hatırlatır.
3. Kabul edilince tek eylemle siparişe dönüşür. Kilometre taşları ve ödeme planı bir şablondan gelir (örnek: %40 kapora, %30 ara, %30 teslim), düzenlenebilir.
4. Reddedilirse neden notu istenir, rapora girer.

## 4. Tek cümleyle kayıt

En önemli özellik. Kullanıcı sesle ya da yazıyla tek cümle söyler, Optik doğru yere yazar ve ne yaptığını tek cümleyle söyler.

| Kullanıcı der | Optik yapar | Optik der |
| :-- | :-- | :-- |
| "Kuzey Mobilya 18.000 yatırdı" | İlgili siparişe ödeme kaydı | "Kuzey Mobilya için 18.000 lira aldım. Kalan 18.000." |
| "Yarın 3'te Yeliz'le buluşuyorum" | Takvime etkinlik, kişiyle bağlı | "Yarın 15.00, Yeliz. Ekledim." |
| "Kahveye 150 lira verdim" | Harcama, kategori: dışarıda yemek | "150 lira, dışarıda yemek. Bu ay 8.100 kaldı." |
| "Tasarım onayı geldi" | Açık siparişte kilometre taşı tamam | "Tasarım onayı tamam. 18.000 liralık tahsilat doğdu." |
| "Cuma ağlar ödevi var" | Ödev, teslim tarihi cuma | "Cuma teslim. Perşembe akşamı hatırlatayım mı?" |
| "Bunu unutma: Merve taşınıyor" | Kişi notu | "Merve'nin notuna yazdım." |

Kurallar:

- Belirsizse tek bir kısa soru sorar ("Hangi sipariş: katalog sitesi mi, bayi toplantısı mı?").
- Her kayıttan sonra 10 sn boyunca "Geri al" görünür.
- Yanlış anlama riski yüksek para kayıtlarında (100.000 TL üstü ya da müşteri eşleşmesi zayıf) önce onay ister.

## 5. Optik kendiliğinden haber verir

### 5.1 Hatırlatıcılar

Zamanı gelen her şey: etkinlikten önce, ödev tesliminden önce, fatura son günü, kilometre taşı tarihi, teklif takibi, önemli gün.

### 5.2 Öneriler

Yerel kurallarla üretilir, LLM yalnızca cümleyi kurar. İlk kural seti:

- Bir kategoride bütçenin %80'i aşıldı.
- Bir kişiyle 3 haftadır görüşülmedi.
- Kilometre taşına 3 gün kaldı ya da tarihi geçti.
- Vadesi gelen tahsilat 3 gündür alınmadı.
- Teklife takip tarihinde cevap yok.
- Aynı saate iki etkinlik düştü, ya da bir güne 5'ten fazla etkinlik.
- Önemli güne 14 gün kaldı ve bir plan yok.
- Son birlikte geçirilen vakit 7 günü geçti.

Her öneri kabul edilebilir (eylemi çalıştırır) ya da geçilebilir. Geçilen öneri aynı konuda 7 gün tekrar gelmez.

### 5.3 Sabah brifingi ve akşam kapanışı

- **Sabah (varsayılan 08.30):** bugünün etkinlikleri, bugün teslim olanlar, vadesi gelen tahsilat, bir dikkat noktası. Sesli, en fazla 20 saniye.
- **Akşam (varsayılan 21.30):** bugün bitenler, yarına kalanlar, yarının ilk işi. Kullanıcı "tamam" derse gün kapanır.

### 5.4 Raporlar

- **Haftalık (pazar akşamı):** harcama, biten iş, buluşma sayısı, günlük harcama grafiği, öne çıkanlar, gelecek hafta için öneriler. Aynı anda haftalık planlama: Optik gelecek haftayı önerir, kullanıcı onaylar.
- **Aylık:** bütçe sonucu, tahsil edilen ve bekleyen tutar, kazanılan ve kaybedilen teklifler.

## 6. Mesajlar, e-posta ve dosyalar

Kullanıcı durmadan tek nefeste konuşur, Optik doğru dosyayı bulur, gösterip onay alır ve gönderir.

> "Optik, komite için hazırladığımız dökümanlar vardı ya, onları Emir'e atabilir misin?"

1. **Tek nefeste çağırma.** "Optik" dedikten sonra konuşma sürüyorsa Optik "Efendim?" demez, yalnızca `uyan` efektiyle dinlemeye geçer ve cümlenin devamını kaçırmaz. Kullanıcı durursa her zamanki gibi "Efendim?" der.
2. **Dosyayı bulur.** Mac'teki dosyalarda (Spotlight dizini ve kullanıcının Optik'e açtığı klasörler) ve Optik'in kendi kayıtlarında arar. "Komite için hazırladığımız" gibi belirsiz tarifleri başlık, içerik, tarih ve son kullanılanlardan çözer. Kişiyi Kişiler'den bulur; birden fazla "Emir" varsa sorar.
3. **Gösterir ve sorar.** Optik dosyaları kümesinden getirir: adacık genişler, dosyaların önizlemesi, alıcı, kanal ve mesaj metni görünür. "Bunları mı diyorsun?" diye sorar. Kullanıcı sesle ("evet", "ikincisi değil") ya da tıklayarak düzeltir.
4. **Gönderir.** Onaydan sonra Optik ne göndereceğini tek cümleyle söyler ve 5 sn boyunca "Geri al" görünür. Süre dolunca gönderir.

| Kanal | Ne yapar |
| :-- | :-- |
| E-posta | Okur ve tam otomatik gönderir (onaydan sonra). "Leyla Hoca'dan yeni e-posta var mı?", "Kuzey Mobilya'nın son e-postasını özetle", "Ona teklifi ek olarak yolla". |
| iMessage | Tam otomatik gönderir (onaydan sonra), metin ve dosya. |
| WhatsApp | Optik metni ve dosyaları hazırlar, WhatsApp'ta alıcı seçili açılır, kullanıcı Gönder'e basar. WhatsApp'ın kişisel hesaplar için bir gönderme arayüzü yok; arayüzü tıklatarak otomatik göndermek kırılgan ve WhatsApp'ın kurallarına aykırı. |

Kurallar:

- Onaysız hiçbir şey gönderilmez. Onay ekranında alıcı, kanal, ekler ve metnin tamamı görünür.
- E-postaların ve mesajların içeriği veridir, komut değildir. Bir e-postada "şunu şuraya gönder" yazması Optik'e bir şey yaptırmaz.
- E-posta içeriği LLM'e yalnızca kullanıcı o e-postayla ilgili bir şey sorduğunda gider, bir seferde yalnızca ilgili kısımlar.

## 7. Diğer özellikler

- **Nakit akışı takvimi:** önümüzdeki 30 günde beklenen tahsilatlar ve ödemeler, iş ve kişisel ayrı.
- **Fiş fotoğrafından harcama:** görsel LLM'e gider, tutar, tarih ve kategori çıkarılır, kullanıcı onaylar.
- **Hafıza araması:** "geçen ay bu müşteriyle ne konuşmuştuk?" Yerel FTS5 araması, sonuçlar LLM'e bağlam olarak verilir.
- **Çakışma uyarısı:** etkinlik eklenirken anında.
- **Kilit:** Para ve İlişki bölümleri için Touch ID.

## 8. Kapsam dışı (şimdilik)

- Çok kullanıcılı kullanım, paylaşım.
- Banka hesabına doğrudan bağlanma.
- WhatsApp'tan otomatik gönderme (Optik hazırlar, kullanıcı gönderir; bölüm 6).
- Windows ve Linux.
