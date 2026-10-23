# Installare BeyondSurvival

Questa guida parte dal presupposto che non hai mai messo su un server FiveM. Seguila dall'alto in basso e avrai un server funzionante in circa 20 minuti.

Ci sono due modi per installare:

- **A - recipe di txAdmin** (il più facile, consigliato)
- **B - installazione manuale** (se vuoi fare ogni passaggio a mano)

---

## Cosa ti serve

- Un PC Windows o un VPS Windows/Linux. Almeno 8 GB di RAM e 10 GB liberi su disco.
- Un **account Cfx.re** e una **license key del server**. Prendi la key su https://portal.cfx.re -> Server Keys -> Generate.
- **MariaDB** (server di database gratuito). Scaricalo da https://mariadb.org/download e installalo con le opzioni di default. Durante l'installazione imposti una **password di root** - segnatela, ti servirà.
- GTA V e FiveM sul PC da cui giochi, per entrare e provare.

---

## A - Installare con la recipe di txAdmin

### 1. Scarica gli artifacts del server

1. Vai su https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/
2. Scarica l'ultima build **recommended** (`server.7z`).
3. Crea una cartella, per esempio `C:\FXServer\server`, ed estrai lì dentro il 7z. Per farlo ti serve 7-Zip (https://7-zip.org).

### 2. Avvia txAdmin

1. Apri la cartella `server` e fai doppio clic su **FXServer.exe**.
2. Si apre una finestra di console e il browser apre txAdmin (se no, vai su http://localhost:40120).
3. Scrivi il PIN mostrato nella console, accedi con il tuo account Cfx.re e crea la password di txAdmin.

### 3. Fai il deploy di BeyondSurvival

1. Nel wizard di setup dai un nome al server e scegli **Remote URL Template**.
2. Incolla questo URL:
   ```
   https://raw.githubusercontent.com/Arcainex/bs19/main/recipe.yaml
   ```
3. Scegli dove vanno i dati del server (quello di default va bene) e clicca avanti.
4. Quando txAdmin chiede la **license key**, incolla la key di portal.cfx.re.
5. Al passaggio del database usa:
   - Host: `localhost`
   - Port: `3306`
   - Username: `root`
   - Password: la password di root di MariaDB di prima
   - Database name: lascialo com'è
6. Clicca **Run Recipe** e aspetta. Scarica il framework, quindi ci vogliono un paio di minuti.
7. Quando finisce, clicca **Save & Run Server**.

Fatto. txAdmin ha già messo nella config la tua license key, il database e il tuo account come admin. Le tabelle del database si creano da sole al primo avvio del server.

Salta a **Dopo il primo avvio** più sotto.

**Opzionale: la mappa.** La mappa non è inclusa. Scaricala da https://github.com/Arcainex/The-Apocalypse-Project, metti la cartella `[the_apocalypse_project]` dentro `resources/[map]`, poi apri `server.cfg` e togli il `##` davanti alla riga `ensure [the_apocalypse_project]`.

---

## B - Installazione manuale

### 1. Artifacts e txAdmin

Fai i passaggi 1 e 2 della parte A.

### 2. Prendi i file

1. Scarica BS19 da https://github.com/Arcainex/bs19 (pulsante verde **Code** > **Download ZIP**).
2. Crea una cartella per i dati del server, per esempio `C:\FXServer\beyondsurvival`, ed estrai lo zip lì dentro. Dentro devi vedere `resources` e `server.cfg`.
3. Scarica oxmysql da https://github.com/overextended/oxmysql/releases (il file `oxmysql.zip`) ed estrailo nella cartella `resources`, così ti ritrovi con `resources\oxmysql`.

### 3. Crea il database

1. Apri **HeidiSQL** (arriva con MariaDB) e collegati con l'utente `root` e la tua password di root.
2. Clic destro sulla connessione -> Create new -> Database. Chiamalo `beyondsurvival`, collation `utf8mb4_unicode_ci`.
3. Lascialo vuoto. BeyondSurvival crea tutte le tabelle al primo avvio.

### 4. Modifica la config

1. Apri `server.cfg` con il Blocco note.
2. Metti la tua license key nella riga `sv_licenseKey`, dove c'è scritto `CHANGEME`.
3. Nella riga `mysql_connection_string` sostituisci `CHANGEME_USER` con `root` e `CHANGEME_PASSWORD` con la tua password di root.
4. Vuoi un nome server tutto tuo? Cambia le righe `sv_hostname` e `sv_projectName`.
5. Aggiungiti come admin (vedi **Rendere qualcuno admin** più sotto).
6. Dopo questo non condividere `server.cfg` con nessuno, contiene la tua key e la tua password.

### 5. Collega txAdmin

1. Nel wizard di txAdmin scegli **Existing Server Data** e seleziona la tua cartella (`C:\FXServer\beyondsurvival`).
2. Seleziona `server.cfg` quando chiede il file di config e avvia il server.
3. In txAdmin vai su **Settings -> FXServer** e controlla che **OneSync** sia su **On**.

---

## Dopo il primo avvio

- Tieni d'occhio la console. Il primo boot ci mette di più perché si creano le tabelle del database e il server mette in cache i suoi file.
- Apri FiveM, premi F8 e scrivi `connect localhost` (o l'IP del tuo VPS).
- Crea il tuo personaggio e sei dentro.

## Rendere qualcuno admin

Gli admin hanno il menu di config con F1, il menu admin, /atlas e i comandi di debug.

1. Fai entrare il giocatore una volta.
2. In txAdmin apri **Players**, clicca sul giocatore e copia la riga che inizia con `license:`.
3. Apri `server.cfg`, vai in fondo e aggiungi:
   ```
   add_principal identifier.license:PASTE_IT_HERE group.superadmin
   ```
   Usa `group.admin` al posto di `group.superadmin` per lo staff normale.
4. Riavvia il server.

Se hai usato la recipe, il tuo account c'è già come `group.admin`. Cambia quella parola in `group.superadmin` se vuoi i diritti completi da owner.

## Cambiare le impostazioni

- Quasi tutto si cambia in gioco con **F1** (solo admin). La modalità Simple ha le cose comuni (quantità di zombie, distanza di spawn, fame, loot...). La modalità Advanced mostra tutto.
- Ogni resource ha anche una cartella `config` con impostazioni commentate, se preferisci modificare i file.

## Problemi?

| Cosa vedi | Cosa fare |
|---|---|
| `Could not connect to database` | User/password sbagliati in `server.cfg`, oppure MariaDB non è avviato. |
| `License key invalid` | Ricopia la key da portal.cfx.re, senza spazi. |
| Il server non è nella lista | Apri le porte 30120 TCP e UDP sul router/firewall. |
| I giocatori restano bloccati nel caricamento | Controlla che OneSync sia On e che la build del gioco sia la 3095. |
| Gli zombie che strisciano scivolano | `nutria_crawl_anims` deve partire prima di `bs_zombies` in `server.cfg`. |

Ancora bloccato? Vieni sul nostro Discord (link su https://bs19.org) e posta le righe rosse della console.
