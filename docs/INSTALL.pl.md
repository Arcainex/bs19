# Instalacja BeyondSurvival

Ten poradnik zakłada, że nigdy nie stawiałeś serwera FiveM. Leć od góry do dołu, a w około 20 minut masz działający serwer.

Są dwa sposoby instalacji:

- **A - recipe z txAdmin** (najłatwiej, polecane)
- **B - instalacja ręczna** (jeśli chcesz zrobić wszystko sam)

---

## Czego potrzebujesz

- Komputera z Windowsem albo VPS-a z Windowsem/Linuxem. Minimum 8 GB RAM i 10 GB wolnego miejsca na dysku.
- **Konta Cfx.re** i **klucza licencyjnego serwera**. Klucz weźmiesz na https://portal.cfx.re -> Server Keys -> Generate.
- **MariaDB** (darmowy serwer bazy danych). Pobierz z https://mariadb.org/download i zainstaluj z domyślnymi opcjami. W trakcie instalacji ustawiasz **hasło roota** - zapisz je, jeszcze się przyda.
- GTA V i FiveM na komputerze, z którego grasz, żeby wejść na serwer i go przetestować.

---

## A - Instalacja z recipe z txAdmin

### 1. Pobierz artifacts serwera

1. Wejdź na https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/
2. Pobierz najnowszy build oznaczony jako **recommended** (`server.7z`).
3. Zrób folder, na przykład `C:\FXServer\server`, i rozpakuj do niego plik 7z. Potrzebujesz do tego 7-Zip (https://7-zip.org).

### 2. Odpal txAdmin

1. Otwórz folder `server` i kliknij dwa razy **FXServer.exe**.
2. Otworzy się okno konsoli, a przeglądarka odpali txAdmin (jak nie, wejdź na http://localhost:40120).
3. Wpisz PIN z konsoli, zaloguj się kontem Cfx.re i ustaw hasło do txAdmin.

### 3. Wgraj BeyondSurvival

1. W kreatorze nadaj serwerowi nazwę i wybierz **Remote URL Template**.
2. Wklej ten URL:
   ```
   https://raw.githubusercontent.com/Arcainex/bs19/main/recipe.yaml
   ```
3. Wybierz, gdzie wylądują dane serwera (domyślne ustawienie jest OK) i kliknij dalej.
4. Gdy txAdmin zapyta o **klucz licencyjny**, wklej klucz z portal.cfx.re.
5. W kroku z bazą danych wpisz:
   - Host: `localhost`
   - Port: `3306`
   - Username: `root`
   - Password: hasło roota do MariaDB z wcześniej
   - Database name: zostaw bez zmian
6. Kliknij **Run Recipe** i poczekaj. Pobiera framework, więc daj mu kilka minut.
7. Jak skończy, kliknij **Save & Run Server**.

I tyle. txAdmin wpisał już do configu twój klucz licencyjny, bazę danych i twoje konto jako admina. Tabele w bazie tworzą się automatycznie przy pierwszym starcie serwera.

Przeskocz do **Po pierwszym starcie** niżej.

**Opcjonalnie: mapa.** Mapa nie jest dołączona. Pobierz ją z https://github.com/Arcainex/The-Apocalypse-Project, wrzuć folder `[the_apocalypse_project]` do `resources/[map]`, a potem w `server.cfg` usuń `##` sprzed linii `ensure [the_apocalypse_project]`.

---

## B - Instalacja ręczna

### 1. Artifacts i txAdmin

Zrób kroki 1 i 2 z części A.

### 2. Weź pliki

1. Pobierz BS19 z https://github.com/Arcainex/bs19 (zielony przycisk **Code** > **Download ZIP**).
2. Zrób folder na dane serwera, na przykład `C:\FXServer\beyondsurvival`, i rozpakuj do niego zipa. W środku powinieneś zobaczyć `resources` i `server.cfg`.
3. Pobierz oxmysql z https://github.com/overextended/oxmysql/releases (plik `oxmysql.zip`) i rozpakuj do folderu `resources`, tak żeby wyszło `resources\oxmysql`.

### 3. Stwórz bazę danych

1. Otwórz **HeidiSQL** (jest w paczce z MariaDB) i połącz się jako użytkownik `root` z twoim hasłem roota.
2. Kliknij prawym na połączenie -> Create new -> Database. Nazwij ją `beyondsurvival`, collation `utf8mb4_unicode_ci`.
3. Zostaw pustą. BeyondSurvival utworzy wszystkie tabele przy pierwszym starcie.

### 4. Edytuj config

1. Otwórz `server.cfg` w Notatniku.
2. Wpisz swój klucz licencyjny w linii `sv_licenseKey`, tam gdzie jest `CHANGEME`.
3. W linii `mysql_connection_string` zamień `CHANGEME_USER` na `root`, a `CHANGEME_PASSWORD` na swoje hasło roota.
4. Chcesz własną nazwę serwera? Zmień linie `sv_hostname` i `sv_projectName`.
5. Dodaj siebie jako admina (zobacz **Jak zrobić kogoś adminem** niżej).
6. Po tym nikomu nie udostępniaj `server.cfg`, są w nim twój klucz i hasło.

### 5. Wskaż to w txAdmin

1. W kreatorze txAdmin wybierz **Existing Server Data** i wskaż swój folder (`C:\FXServer\beyondsurvival`).
2. Gdy zapyta o plik configu, wybierz `server.cfg` i odpal serwer.
3. W txAdmin wejdź w **Settings -> FXServer** i upewnij się, że **OneSync** jest na **On**.

---

## Po pierwszym starcie

- Patrz na konsolę. Pierwszy start trwa dłużej, bo tworzą się tabele w bazie i serwer cache'uje swoje pliki.
- Odpal FiveM, wciśnij F8 i wpisz `connect localhost` (albo IP twojego VPS-a).
- Stwórz postać i jesteś w grze.

## Jak zrobić kogoś adminem

Admini dostają menu configu pod F1, menu admina, /atlas i komendy debugowe.

1. Niech gracz wejdzie na serwer raz.
2. W txAdmin otwórz **Players**, kliknij gracza i skopiuj linię zaczynającą się od `license:`.
3. Otwórz `server.cfg`, zjedź na sam dół i dopisz:
   ```
   add_principal identifier.license:PASTE_IT_HERE group.superadmin
   ```
   Dla zwykłej ekipy daj `group.admin` zamiast `group.superadmin`.
4. Zrestartuj serwer.

Jeśli użyłeś recipe, twoje konto już tam jest jako `group.admin`. Zmień to słowo na `group.superadmin`, jeśli chcesz pełne prawa właściciela.

## Zmiana ustawień

- Większość rzeczy zmienisz w grze pod **F1** (tylko admin). Simple mode ma najczęstsze rzeczy (ilość zombie, dystans spawnu, głód, loot...). Advanced mode pokazuje wszystko.
- Każdy resource ma też folder `config` z opisanymi ustawieniami, jeśli wolisz edytować pliki.

## Problemy?

| Co widzisz | Co robić |
|---|---|
| `Could not connect to database` | Zły user/hasło w `server.cfg` albo MariaDB nie działa. |
| `License key invalid` | Skopiuj klucz jeszcze raz z portal.cfx.re, bez spacji. |
| Serwera nie ma na liście serwerów | Otwórz porty 30120 TCP i UDP na routerze/firewallu. |
| Gracze zawieszają się przy ładowaniu | Sprawdź, czy OneSync jest On i czy build gry to 3095. |
| Czołgające się zombie ślizgają się | `nutria_crawl_anims` musi startować przed `bs_zombies` w `server.cfg`. |

Dalej nie działa? Wbij na naszego Discorda (link na https://bs19.org) i wrzuć czerwone linie z konsoli.
