# BeyondSurvival Kurulumu

Bu rehber daha önce hiç FiveM sunucusu kurmadığını varsayıyor. Baştan sona sırayla takip et, yaklaşık 20 dakikada çalışan bir sunucun olur.

İki kurulum yolu var:

- **A - txAdmin recipe** (en kolayı, tavsiye edilen)
- **B - manuel kurulum** (her adımı kendin yapmak istersen)

---

## Ne lazım

- Bir Windows PC ya da Windows/Linux VPS. En az 8 GB RAM ve 10 GB boş disk alanı.
- Bir **Cfx.re hesabı** ve bir **sunucu lisans anahtarı**. Anahtarı https://portal.cfx.re -> Server Keys -> Generate yolundan al.
- **MariaDB** (ücretsiz veritabanı sunucusu). https://mariadb.org/download adresinden indir, varsayılan ayarlarla kur. Kurulum sırasında bir **root şifresi** belirliyorsun - bir yere yaz, lazım olacak.
- Oynadığın PC'de GTA V ve FiveM, girip test etmek için.

---

## A - txAdmin recipe ile kurulum

### 1. Sunucu artifacts dosyalarını indir

1. https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/ adresine git.
2. En son **recommended** build'i indir (`server.7z`).
3. Bir klasör aç, mesela `C:\FXServer\server`, ve 7z'yi içine çıkar. Bunun için 7-Zip lazım (https://7-zip.org).

### 2. txAdmin'i başlat

1. `server` klasörünü aç ve **FXServer.exe** dosyasına çift tıkla.
2. Bir konsol penceresi açılır ve tarayıcın txAdmin'i açar (açılmazsa http://localhost:40120 adresine git).
3. Konsolda yazan PIN'i gir, Cfx.re hesabınla giriş yap ve txAdmin şifreni oluştur.

### 3. BeyondSurvival'ı kur

1. Kurulum sihirbazında sunucuna bir isim ver ve **Remote URL Template** seç.
2. Şu URL'yi yapıştır:
   ```
   https://raw.githubusercontent.com/Arcainex/bs19/main/recipe.yaml
   ```
3. Sunucu verilerinin nereye gideceğini seç (varsayılan olur) ve ileri'ye bas.
4. txAdmin **lisans anahtarını** sorunca portal.cfx.re'den aldığın anahtarı yapıştır.
5. Veritabanı adımında şunları kullan:
   - Host: `localhost`
   - Port: `3306`
   - Username: `root`
   - Password: biraz önceki MariaDB root şifresi
   - Database name: olduğu gibi bırak
6. **Run Recipe**'ye bas ve bekle. Framework'ü indiriyor, o yüzden birkaç dakika ver.
7. Bitince **Save & Run Server**'a bas.

Bu kadar. txAdmin lisans anahtarını, veritabanını ve kendi hesabını admin olarak config'e zaten yazdı. Veritabanı tabloları sunucu ilk açıldığında otomatik oluşturulur.

Aşağıdaki **İlk açılıştan sonra** kısmına geç.

**İsteğe bağlı: harita.** Harita pakete dahil değil. https://github.com/Arcainex/The-Apocalypse-Project adresinden indir, `[the_apocalypse_project]` klasörünü `resources/[map]` içine koy, sonra `server.cfg` dosyasında `ensure [the_apocalypse_project]` satırının başındaki `##` işaretlerini sil.

---

## B - Manuel kurulum

### 1. Artifacts ve txAdmin

A bölümündeki 1. ve 2. adımları yap.

### 2. Dosyaları al

1. BS19'u https://github.com/Arcainex/bs19 adresinden indir (yeşil **Code** düğmesi > **Download ZIP**).
2. Sunucu verileri için bir klasör aç, mesela `C:\FXServer\beyondsurvival`, ve zip'i içine çıkar. İçinde `resources` ve `server.cfg` görmelisin.
3. oxmysql'i https://github.com/overextended/oxmysql/releases adresinden indir (`oxmysql.zip` dosyası) ve `resources` klasörüne çıkar, yani sonuçta `resources\oxmysql` olsun.

### 3. Veritabanını oluştur

1. **HeidiSQL**'i aç (MariaDB ile birlikte geliyor) ve `root` kullanıcısı ve root şifrenle bağlan.
2. Bağlantıya sağ tıkla -> Create new -> Database. Adı `beyondsurvival`, collation `utf8mb4_unicode_ci` olsun.
3. Boş bırak. BeyondSurvival bütün tabloları ilk açılışta oluşturur.

### 4. Config'i düzenle

1. `server.cfg` dosyasını Not Defteri ile aç.
2. Lisans anahtarını `sv_licenseKey` satırında `CHANGEME` yazan yere koy.
3. `mysql_connection_string` satırında `CHANGEME_USER` yerine `root`, `CHANGEME_PASSWORD` yerine root şifreni yaz.
4. Kendi sunucu adını mı istiyorsun? `sv_hostname` ve `sv_projectName` satırlarını değiştir.
5. Kendini admin olarak ekle (aşağıdaki **Birini admin yapmak** kısmına bak).
6. Bundan sonra `server.cfg` dosyasını kimseyle paylaşma, içinde anahtarın ve şifren var.

### 5. txAdmin'i buraya yönlendir

1. txAdmin kurulum sihirbazında **Existing Server Data** seç ve klasörünü göster (`C:\FXServer\beyondsurvival`).
2. Config dosyasını sorunca `server.cfg` seç ve sunucuyu başlat.
3. txAdmin'de **Settings -> FXServer** kısmına git ve **OneSync**'in **On** olduğundan emin ol.

---

## İlk açılıştan sonra

- Konsola göz at. İlk açılış daha uzun sürer çünkü veritabanı tabloları oluşturulur ve sunucu dosyalarını cache'ler.
- FiveM'i aç, F8'e bas ve `connect localhost` yaz (ya da VPS IP'ni).
- Karakterini oluştur, içeridesin.

## Birini admin yapmak

Adminler F1 config menüsünü, admin menüsünü, /atlas komutunu ve debug komutlarını alır.

1. Oyuncu bir kere sunucuya girsin.
2. txAdmin'de **Players**'ı aç, oyuncuya tıkla ve `license:` ile başlayan satırı kopyala.
3. `server.cfg` dosyasını aç, en alta in ve şunu ekle:
   ```
   add_principal identifier.license:PASTE_IT_HERE group.superadmin
   ```
   Normal yetkililer için `group.superadmin` yerine `group.admin` kullan.
4. Sunucuyu yeniden başlat.

Recipe kullandıysan kendi hesabın zaten `group.admin` olarak orada. Tam sahip yetkisi istiyorsan o kelimeyi `group.superadmin` yap.

## Ayarları değiştirmek

- Çoğu şeyi oyun içinde **F1** ile değiştirebilirsin (sadece admin). Simple mode'da sık kullanılanlar var (zombi sayısı, spawn mesafesi, açlık, loot...). Advanced mode her şeyi gösterir.
- Her resource'un ayrıca yorum satırlı ayarların olduğu bir `config` klasörü var, dosya düzenlemeyi tercih edersen.

## Sorun mu var?

| Gördüğün | Yapman gereken |
|---|---|
| `Could not connect to database` | `server.cfg` içinde kullanıcı/şifre yanlış ya da MariaDB çalışmıyor. |
| `License key invalid` | Anahtarı portal.cfx.re'den boşluksuz olarak tekrar kopyala. |
| Sunucu sunucu listesinde yok | Router/firewall'da 30120 TCP ve UDP portlarını aç. |
| Oyuncular yüklemede takılıyor | OneSync'in On olduğundan ve oyun build'inin 3095 olduğundan emin ol. |
| Sürünen zombiler kayıyor | `server.cfg` içinde `nutria_crawl_anims`, `bs_zombies`'ten önce başlamalı. |

Hâlâ olmadı mı? Discord'umuza gel (link https://bs19.org adresinde) ve konsoldaki kırmızı satırları at.
