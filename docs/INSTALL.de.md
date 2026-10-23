# BeyondSurvival installieren

Diese Anleitung geht davon aus, dass du noch nie einen FiveM-Server aufgesetzt hast. Arbeite sie von oben nach unten ab, dann läuft dein Server in etwa 20 Minuten.

Es gibt zwei Wege:

- **A - txAdmin Recipe** (am einfachsten, empfohlen)
- **B - manuelle Installation** (wenn du alles selbst machen willst)

---

## Was du brauchst

- Einen Windows-PC oder einen Windows/Linux-VPS. Mindestens 8 GB RAM und 10 GB freier Speicherplatz.
- Einen **Cfx.re-Account** und einen **Server-Lizenzschlüssel**. Den Key bekommst du unter https://portal.cfx.re -> Server Keys -> Generate.
- **MariaDB** (kostenloser Datenbankserver). Lad es von https://mariadb.org/download runter und installier es mit den Standardoptionen. Bei der Installation setzt du ein **Root-Passwort** - schreib es auf, du brauchst es noch.
- GTA V und FiveM auf dem PC, von dem aus du spielst, zum Beitreten und Testen.

---

## A - Installation mit dem txAdmin Recipe

### 1. Server-Artifacts herunterladen

1. Geh auf https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/
2. Lad den neuesten **recommended** Build runter (`server.7z`).
3. Leg einen Ordner an, z. B. `C:\FXServer\server`, und entpack die 7z dort rein. Dafür brauchst du 7-Zip (https://7-zip.org).

### 2. txAdmin starten

1. Öffne den Ordner `server` und doppelklick auf **FXServer.exe**.
2. Ein Konsolenfenster geht auf und dein Browser öffnet txAdmin (falls nicht, geh auf http://localhost:40120).
3. Tipp die PIN aus der Konsole ein, logg dich mit deinem Cfx.re-Account ein und leg das txAdmin-Passwort fest.

### 3. BeyondSurvival deployen

1. Gib im Setup-Assistenten deinem Server einen Namen und wähl **Remote URL Template**.
2. Füg diese URL ein:
   ```
   https://raw.githubusercontent.com/Arcainex/bs19/main/recipe.yaml
   ```
3. Wähl, wo die Serverdaten hinkommen (der Standard passt) und klick auf weiter.
4. Wenn txAdmin nach dem **Lizenzschlüssel** fragt, füg den Key von portal.cfx.re ein.
5. Im Datenbank-Schritt nimmst du:
   - Host: `localhost`
   - Port: `3306`
   - Username: `root`
   - Password: das MariaDB-Root-Passwort von vorhin
   - Database name: so lassen, wie es ist
6. Klick auf **Run Recipe** und warte. Es lädt das Framework, das dauert ein paar Minuten.
7. Wenn es durch ist, klick auf **Save & Run Server**.

Das war's. txAdmin hat deinen Lizenzschlüssel, die Datenbank und deinen eigenen Account als Admin schon in die Config geschrieben. Die Datenbanktabellen werden beim ersten Serverstart automatisch angelegt.

Spring weiter zu **Nach dem ersten Start** unten.

**Optional: die Map.** Die Map ist nicht enthalten. Lad sie von https://github.com/Arcainex/The-Apocalypse-Project herunter, leg den Ordner `[the_apocalypse_project]` in `resources/[map]` und entferne dann in der `server.cfg` das `##` vor der Zeile `ensure [the_apocalypse_project]`.

---

## B - Manuelle Installation

### 1. Artifacts und txAdmin

Mach die Schritte 1 und 2 aus Teil A.

### 2. Dateien holen

1. Lad BS19 von https://github.com/Arcainex/bs19 runter (grüner **Code**-Button > **Download ZIP**).
2. Leg einen Ordner für die Serverdaten an, z. B. `C:\FXServer\beyondsurvival`, und entpack die Zip dort rein. Darin solltest du `resources` und `server.cfg` sehen.
3. Lad oxmysql von https://github.com/overextended/oxmysql/releases runter (die Datei `oxmysql.zip`) und entpack sie in den Ordner `resources`, sodass du am Ende `resources\oxmysql` hast.

### 3. Datenbank anlegen

1. Öffne **HeidiSQL** (kommt mit MariaDB) und verbinde dich mit dem User `root` und deinem Root-Passwort.
2. Rechtsklick auf die Verbindung -> Create new -> Database. Nenn sie `beyondsurvival`, Collation `utf8mb4_unicode_ci`.
3. Lass sie leer. BeyondSurvival legt beim ersten Start alle Tabellen an.

### 4. Config bearbeiten

1. Öffne `server.cfg` mit Notepad.
2. Trag deinen Lizenzschlüssel in der Zeile `sv_licenseKey` ein, da wo `CHANGEME` steht.
3. Ersetz in der Zeile `mysql_connection_string` `CHANGEME_USER` durch `root` und `CHANGEME_PASSWORD` durch dein Root-Passwort.
4. Willst du einen eigenen Servernamen? Ändere die Zeilen `sv_hostname` und `sv_projectName`.
5. Trag dich selbst als Admin ein (siehe **Jemanden zum Admin machen** unten).
6. Gib `server.cfg` danach an niemanden weiter, da stehen dein Key und dein Passwort drin.

### 5. txAdmin darauf zeigen lassen

1. Wähl im txAdmin-Setup-Assistenten **Existing Server Data** und such deinen Ordner aus (`C:\FXServer\beyondsurvival`).
2. Wähl `server.cfg`, wenn nach der Config-Datei gefragt wird, und starte den Server.
3. Geh in txAdmin auf **Settings -> FXServer** und check, dass **OneSync** auf **On** steht.

---

## Nach dem ersten Start

- Behalt die Konsole im Auge. Der erste Start dauert länger, weil die Datenbanktabellen angelegt und der Server seine Dateien cacht.
- Öffne FiveM, drück F8 und tipp `connect localhost` ein (oder die IP deines VPS).
- Erstell deinen Charakter und du bist drin.

## Jemanden zum Admin machen

Admins bekommen das F1-Config-Menü, das Admin-Menü, /atlas und die Debug-Commands.

1. Lass den Spieler einmal joinen.
2. Öffne in txAdmin **Players**, klick auf den Spieler und kopier die Zeile, die mit `license:` anfängt.
3. Öffne `server.cfg`, scroll ans Ende und füg hinzu:
   ```
   add_principal identifier.license:PASTE_IT_HERE group.superadmin
   ```
   Nimm `group.admin` statt `group.superadmin` für normales Staff.
4. Starte den Server neu.

Wenn du das Recipe benutzt hast, steht dein eigener Account schon als `group.admin` drin. Änder das Wort in `group.superadmin`, wenn du volle Owner-Rechte willst.

## Einstellungen ändern

- Das meiste lässt sich im Spiel mit **F1** ändern (nur Admins). Der Simple mode hat das Übliche (Zombie-Menge, Spawn-Distanz, Hunger, Loot...). Der Advanced mode zeigt alles.
- Jede Resource hat außerdem einen `config`-Ordner mit kommentierten Einstellungen, falls du lieber Dateien editierst.

## Probleme?

| Was du siehst | Was du tun kannst |
|---|---|
| `Could not connect to database` | Falscher User/Passwort in `server.cfg`, oder MariaDB läuft nicht. |
| `License key invalid` | Kopier den Key nochmal von portal.cfx.re, ohne Leerzeichen. |
| Server nicht in der Serverliste | Öffne die Ports 30120 TCP und UDP in Router/Firewall. |
| Spieler hängen beim Laden fest | Stell sicher, dass OneSync On ist und der Game-Build 3095 ist. |
| Kriechende Zombies rutschen herum | `nutria_crawl_anims` muss in `server.cfg` vor `bs_zombies` starten. |

Immer noch stuck? Komm auf unseren Discord (Link auf https://bs19.org) und poste die roten Zeilen aus der Konsole.
