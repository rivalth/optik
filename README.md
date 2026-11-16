# Optik

Optik, MacBook çentiğinde yaşayan, Türkçe konuşan kişisel bir "ikinci beyin" asistanıdır. "Optik" diye seslenince kümesinden çıkar, "Efendim?" der, söylediğini dinler, işi yapar ve kendi sesiyle yanıt verir. Takvimi, kişileri, dersleri, projeleri, bütçeyi, ilişkiyi ve müşteri siparişlerini tutar, raporlar ve hatırlatıcılarla kendisi haber verir.

Karakteri altı kırık bir yumurta: kırıktan civciv ayakları çıkıyor, kabuktaki çatlaktan gözleri ve gagası görünüyor.

![Optik'in ruh halleri](assets/karakter/optik-ruh-halleri.png)

> **Durum:** tasarım ve tarif aşamasında. Kod henüz yok. Sıradaki iş `docs/04-yol-haritasi.md` içindeki Aşama 0.

## Kimin için

Optik tek kişilik bir asistandır ve yalnızca kendi Mac'inde çalışır. Hazır paket dağıtılmaz: depoyu klonla, kendi Apple geliştirici kimliğinle derle, kendi anahtarlarını gir, kendi asistanını kur.

- macOS 14 ve üstü, Apple Silicon
- Çentikli MacBook (çentiksiz ekranda yüzen bir hap olarak görünür)

## Gereken hesaplar ve anahtarlar

- Claude API anahtarı.
- Bir konuşma sentezi servisi hesabı (Optik'in sesi için).
- Uyandırma kelimesi için Picovoice erişim anahtarı (Porcupine kullanılacaksa).

Anahtarlar depoya girmez. Uygulama bunları ilk açılışta sorar ve Keychain'e yazar.

## İçindekiler

| Yol | Ne |
| :-- | :-- |
| `CLAUDE.md` | Claude Code'un her oturumda okuduğu kısa talimat: kararlar, kurallar, performans bütçeleri, git kuralları |
| `docs/01-urun.md` | Optik ne yapar: yüzeyler, bölümler, sipariş kartı, tek cümleyle kayıt, öneri ve rapor kuralları |
| `docs/02-mimari.md` | Teknik yapı: çentik adacığı, ses hattı, LLM, veri, performans, gizlilik, kaynaklar |
| `docs/03-karakter.md` | Karakterin ölçüleri, katmanları, ruh halleri, animasyon ve ses tablosu, renkler |
| `docs/04-yol-haritasi.md` | Aşamalar, kabul kriterleri, verilen kararlar, açık sorular |
| `veri/sema.sql` | SQLite şeması (örnek veriyle sınandı) |
| `veri/ornek-veri.json` | Geliştirme için uydurma örnek veri (tasarımlardaki verinin aynısı) |
| `llm/sistem-istemi.md` | Optik'in kişiliği ve çalışma kuralları, tur bağlamı biçimi, sınama cümleleri |
| `llm/araclar.json` | 27 araç tanımı (Claude araç kullanımı biçiminde) |
| `llm/sabit-cumleler.json` | Önceden seslendirilecek 18 cümle |
| `llm/ses-kimligi.md` | Optik'in sesinin tarifi ve seçim yöntemi |
| `assets/` | Karakter (SVG, PNG), animasyon referansı, kümes, uygulama ikonu seti, arayüz ikonları, ses efektleri, tasarım tokenları |
| `tasarim-kaynak/` | Ekran tasarımlarının kaynak dosyaları (referans) |

Karakterin çalışan referansı için `assets/animasyon/optik-demo.html` dosyasını tarayıcıda aç.

## Katkı

- `main` korumalıdır. Her değişiklik bir dalda yapılır ve PR ile gelir.
- Commit mesajları ve PR başlıkları [Conventional Commits](https://www.conventionalcommits.org/) biçimindedir: `feat(island): add notch panel`.
- Depoya gerçek kişisel veri, anahtar ya da ses kaydı girmez. Her PR'da otomatik sır taraması çalışır.

Ayrıntılar `CLAUDE.md` içindeki "Depo ve git kuralları" bölümünde.

## Lisans

- Kod ve belgeler: [MIT](LICENSE).
- Görseller, karakter, ses efektleri ve ekran tasarımları (`assets/`, `tasarim-kaynak/`): [CC BY 4.0](LICENSE-ASSETS). Kullanırken Optik'e atıf ver.
