# Installing BeyondSurvival

This guide assumes you never ran a FiveM server before. Follow it top to bottom and you'll have a working server in about 20 minutes.

There are two ways to install:

- **A - txAdmin recipe** (easiest, recommended)
- **B - manual install** (if you want to do every step yourself)

---

## What you need

- A Windows PC or a Windows/Linux VPS. At least 8 GB RAM and 10 GB free disk space.
- A **Cfx.re account** and a **server license key**. Get the key at https://portal.cfx.re -> Server Keys -> Generate.
- **MariaDB** (free database server). Download it from https://mariadb.org/download and install it with the default options. During the install you set a **root password** - write it down, you'll need it.
- GTA V and FiveM on the PC you play from, to join and test.

---

## A - Install with the txAdmin recipe

### 1. Download the server artifacts

1. Go to https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/
2. Download the latest **recommended** build (`server.7z`).
3. Make a folder, for example `C:\FXServer\server`, and extract the 7z into it. You need 7-Zip for that (https://7-zip.org).

### 2. Start txAdmin

1. Open the `server` folder and double-click **FXServer.exe**.
2. A console window opens and your browser opens txAdmin (if it doesn't, go to http://localhost:40120).
3. Type the PIN shown in the console, log in with your Cfx.re account and create the txAdmin password.

### 3. Deploy BeyondSurvival

1. In the setup wizard give your server a name and pick **Remote URL Template**.
2. Paste this URL:
   ```
   https://raw.githubusercontent.com/Arcainex/bs19/main/recipe.yaml
   ```
3. Choose where the server data goes (the default is fine) and click next.
4. When txAdmin asks for the **license key**, paste the key from portal.cfx.re.
5. On the database step use:
   - Host: `localhost`
   - Port: `3306`
   - Username: `root`
   - Password: the MariaDB root password from before
   - Database name: leave it as it is
6. Click **Run Recipe** and wait. It downloads the framework, so give it a few minutes.
7. When it finishes, click **Save & Run Server**.

That's it. txAdmin already put your license key, the database and your own account as admin in the config. The database tables are created automatically the first time the server starts.

Jump to **After the first start** below.

**Optional: the map.** The map is not included. Download it from https://github.com/Arcainex/The-Apocalypse-Project, put the `[the_apocalypse_project]` folder inside `resources/[map]`, then open `server.cfg` and remove the `##` in front of the `ensure [the_apocalypse_project]` line.

---

## B - Manual install

### 1. Artifacts and txAdmin

Do steps 1 and 2 from part A.

### 2. Get the files

1. Download BS19 from https://github.com/Arcainex/bs19 (green **Code** button > **Download ZIP**).
2. Make a folder for the server data, for example `C:\FXServer\beyondsurvival`, and extract the zip into it. You should see `resources` and `server.cfg` inside.
3. Download oxmysql from https://github.com/overextended/oxmysql/releases (the `oxmysql.zip` file) and extract it into the `resources` folder, so you end up with `resources\oxmysql`.

### 3. Create the database

1. Open **HeidiSQL** (it comes with MariaDB) and connect with user `root` and your root password.
2. Right-click the connection -> Create new -> Database. Name it `beyondsurvival`, collation `utf8mb4_unicode_ci`.
3. Leave it empty. BeyondSurvival creates every table on the first start.

### 4. Edit the config

1. Open `server.cfg` with Notepad.
2. Put your license key in the `sv_licenseKey` line where it says `CHANGEME`.
3. In the `mysql_connection_string` line replace `CHANGEME_USER` with `root` and `CHANGEME_PASSWORD` with your root password.
4. Want your own server name? Change the `sv_hostname` and `sv_projectName` lines.
5. Add yourself as admin (see **Making someone admin** below).
6. Don't share `server.cfg` with anyone after this, it has your key and password in it.

### 5. Point txAdmin at it

1. In the txAdmin setup wizard pick **Existing Server Data** and select your folder (`C:\FXServer\beyondsurvival`).
2. Select `server.cfg` when it asks for the config file and start the server.
3. In txAdmin go to **Settings -> FXServer** and make sure **OneSync** is set to **On**.

---

## After the first start

- Watch the console. The first boot takes longer because the database tables are created and the server caches its files.
- Open FiveM, press F8 and type `connect localhost` (or your VPS IP).
- Create your character and you're in.

## Making someone admin

Admins get the F1 config menu, the admin menu, /atlas and the debug commands.

1. Have the player join once.
2. In txAdmin open **Players**, click the player and copy the line that starts with `license:`.
3. Open `server.cfg`, go to the bottom and add:
   ```
   add_principal identifier.license:PASTE_IT_HERE group.superadmin
   ```
   Use `group.admin` instead of `group.superadmin` for normal staff.
4. Restart the server.

If you used the recipe, your own account is already there as `group.admin`. Change that word to `group.superadmin` if you want full owner rights.

## Changing settings

- Most things can be changed in game with **F1** (admin only). Simple mode has the common stuff (zombie amount, spawn distance, hunger, loot...). Advanced mode shows everything.
- Every resource also has a `config` folder with commented settings if you prefer editing files.

## Problems?

| What you see | What to do |
|---|---|
| `Could not connect to database` | Wrong user/password in `server.cfg`, or MariaDB isn't running. |
| `License key invalid` | Copy the key again from portal.cfx.re, no spaces. |
| Server not in the server list | Open ports 30120 TCP and UDP in your router/firewall. |
| Players get stuck loading | Make sure OneSync is On and the game build is 3095. |
| Crawling zombies slide around | `nutria_crawl_anims` must start before `bs_zombies` in `server.cfg`. |

Still stuck? Come to our Discord (link on https://bs19.org) and post the red lines from the console.
