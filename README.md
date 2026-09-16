# 🎬 CineLog

<div align="center">

![CineLog Banner](https://img.shields.io/badge/CineLog-v1.0.0-9333ea?style=for-the-badge&logo=film)
![Rails](https://img.shields.io/badge/Ruby_on_Rails-8.1-CC0000?style=for-the-badge&logo=ruby-on-rails&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?style=for-the-badge&logo=postgresql&logoColor=white)
![Tailwind CSS](https://img.shields.io/badge/Tailwind_CSS-v4-06B6D4?style=for-the-badge&logo=tailwindcss&logoColor=white)
![Hotwire](https://img.shields.io/badge/Hotwire-Turbo_%2B_Stimulus-FFDB58?style=for-the-badge)

<p align="center">
  <b>Modern, şık ve koyu tema odaklı film & dizi takip ve topluluk platformu.</b>
  <br />
  Letterboxd ve Netflix estetiğini bir araya getiren mat koyu mor ve siyah palet, gerçek zamanlı TMDB entegrasyonu ve interaktif topluluk deneyimi.
</p>

</div>

---

## ✨ Özellikler

- **🌟 Sinematik Hero Banner & Keşif**: Günün öne çıkan yapımları için yüksek çözünürlüklü dinamik arka plan ve çift gradyan geçişli modern hero alanı.
- **⚡ Anlık Arama & Otomatik Tamamlama (Autocomplete)**: Arama kutusunda yazarken Hotwire (Stimulus) ile anında açılan zengin öneri kartları (puan, tür, yıl ve afiş).
- **📋 İzleme Listesi & Geçmişi (Watchlist)**:
  - İzleyeceklerim ve İzlediklerim olarak sekmeli takip.
  - 10 üzerinden yıldızlı puanlama sistemi.
  - Turbo Stream ile sayfayı yenilemeden tek tıkla liste durumu güncelleme ve kaldırma.
- **💬 Topluluk & Tartışmalar (Community Forum)**:
  - Film ve dizi tavsiyeleri isteme, teorileri paylaşma.
  - Başlıklara doğrudan TMDB yapımı bağlayabilme (`🎬 Film Tartışması`, `📺 Dizi Tartışması`).
  - Yanıtlar ve dinamik etkileşimler.
- **📱 Kusursuz Mobil Uyumluluk**:
  - Mobil cihazlar için yerel uygulama hissi veren alt navigasyon barı (Bottom Navigation Bar).
  - Katlanabilir ve hızlı erişimli arama çubuğu.
- **🎨 Modern Pitch-Black & Amethyst Purple Tema**:
  - Tailwind CSS v4 ile sıfırdan geliştirilmiş derin siyah (`#0a0a0c`) ve neon/ametist moru (`#9333ea`) renk paleti.
  - İnce cam efektleri (Glassmorphism) ve yumuşak ambiyans ışıltıları.

---

## 🛠️ Teknoloji Yığını

| Katman | Teknoloji |
| :--- | :--- |
| **Backend** | Ruby 3.x, Ruby on Rails 8.1 |
| **Veritabanı** | PostgreSQL |
| **Frontend** | Hotwire (Turbo 8, Stimulus 3), Tailwind CSS v4 |
| **Kimlik Doğrulama** | Devise |
| **Dış Servisler** | The Movie Database (TMDB) API v3 |
| **Test** | Rails Minitest & Fixtures |

---

## 🚀 Kurulum ve Çalıştırma

### Gereksinimler
- Ruby 3.x+
- PostgreSQL
- TMDB API Anahtarı (The Movie Database)

### 1. Projeyi Klonlayın
```bash
git clone git@github.com:Ahmetdemirci17/CineLog.git
cd CineLog
```

### 2. Bağımlılıkları Yükleyin
```bash
bundle install
```

### 3. Veritabanını Hazırlayın
PostgreSQL servisinizin çalıştığından emin olduktan sonra:
```bash
bin/rails db:create
bin/rails db:migrate
```

### 4. Ortam Değişkenlerini Ayarlayın
Proje kök dizininde `.env` dosyası oluşturun:
```env
TMDB_API_KEY=senin_tmdb_api_anahtarin
TMDB_BASE_URL=https://api.themoviedb.org/3
```

### 5. Uygulamayı Başlatın
Tailwind CSS watcher ve Rails sunucusunu birlikte çalıştırmak için:
```bash
bin/dev
```
Tarayıcınızdan `http://localhost:3000` adresine gidin.

---

## 🧪 Testleri Çalıştırma

```bash
bin/rails test
```

---

## 📄 Lisans

Bu proje MIT lisansı altında lisanslanmıştır. Detaylar için `LICENSE` dosyasına bakabilirsiniz.
