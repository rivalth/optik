# Ekran tasarımlarının kaynağı

Bu dört dosya tasarım panosundaki çalışmaların kaynak kodudur. Tasarım aracının kendi biçimindedir (`.dc.html`), tarayıcıda tek başına çalışmaz. Yerleşim, metinler, renkler, durum mantığı ve örnek veri için **okunacak referans** olarak buradadır.

| Dosya | Ne gösterir |
| :-- | :-- |
| `01-uygulama.dc.html` | Bugün, Takvim, Kişiler, Dersler, Projeler bölümleri (390 × 844 telefon çerçevesinde) |
| `02-ikinci-beyin.dc.html` | Özet, Para, İlişki, İşler (müşteri siparişleri + yapılacaklar), Rapor bölümleri |
| `03-mac-centik.dc.html` | Çentik adacığı ve kümes: bekliyor → efendim → dinliyor → yanıtlıyor akışı |
| `04-karakter.dc.html` | Yedi ruh hali ve sesleri |

Nasıl okunur:

- `<x-dc>` içindeki işaretleme ekranın yerleşimidir. Satır içi `style` değerleri gerçek ölçülerdir.
- `{{ad}}` yer tutucuları dosyanın sonundaki `renderVals()` fonksiyonundan gelir. Optik'in her bölümde ne söylediği ve hangi ruh haline geçtiği oradadır.
- Karakterin CSS sınıfları bu dosyalarda `tik-` ve `m-` önekiyle geçer. Güncel ve temiz hali `assets/animasyon/optik.css` içindedir, onu esas al.
- Ekranlar telefon boyutunda çizildi. Mac penceresinde aynı bölümler kenar çubuklu bir yerleşimde sunulur, kart yapısı ve içerik aynı kalır.

Henüz tasarımı çizilmemiş, yalnızca `docs/01-urun.md` içinde tarif edilen bölümler: Müşteriler, Teklifler, nakit akışı takvimi, Hafıza araması, fiş okuma, sabah brifingi ve akşam kapanışı.
