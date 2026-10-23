# Installer BeyondSurvival

Ce guide part du principe que t'as jamais monté de serveur FiveM. Suis-le de haut en bas et t'auras un serveur qui tourne en environ 20 minutes.

Il y a deux façons d'installer :

- **A - recipe txAdmin** (la plus simple, recommandée)
- **B - installation manuelle** (si tu veux tout faire toi-même)

---

## Ce qu'il te faut

- Un PC Windows ou un VPS Windows/Linux. Minimum 8 Go de RAM et 10 Go libres sur le disque.
- Un **compte Cfx.re** et une **license key de serveur**. Récupère la clé sur https://portal.cfx.re -> Server Keys -> Generate.
- **MariaDB** (serveur de base de données gratuit). Télécharge-le sur https://mariadb.org/download et installe-le avec les options par défaut. Pendant l'install, tu définis un **mot de passe root** - note-le, t'en auras besoin.
- GTA V et FiveM sur le PC depuis lequel tu joues, pour te connecter et tester.

---

## A - Installer avec la recipe txAdmin

### 1. Télécharge les artifacts du serveur

1. Va sur https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/
2. Télécharge la dernière build **recommended** (`server.7z`).
3. Crée un dossier, par exemple `C:\FXServer\server`, et extrais le 7z dedans. Il te faut 7-Zip pour ça (https://7-zip.org).

### 2. Lance txAdmin

1. Ouvre le dossier `server` et double-clique sur **FXServer.exe**.
2. Une fenêtre de console s'ouvre et ton navigateur ouvre txAdmin (sinon, va sur http://localhost:40120).
3. Tape le PIN affiché dans la console, connecte-toi avec ton compte Cfx.re et crée le mot de passe txAdmin.

### 3. Déploie BeyondSurvival

1. Dans l'assistant de config, donne un nom à ton serveur et choisis **Remote URL Template**.
2. Colle cette URL :
   ```
   https://raw.githubusercontent.com/Arcainex/bs19/main/recipe.yaml
   ```
3. Choisis où vont les données du serveur (le dossier par défaut est bon) et clique sur suivant.
4. Quand txAdmin demande la **license key**, colle la clé de portal.cfx.re.
5. À l'étape de la base de données, mets :
   - Host: `localhost`
   - Port: `3306`
   - Username: `root`
   - Password: le mot de passe root de MariaDB de tout à l'heure
   - Database name: laisse tel quel
6. Clique sur **Run Recipe** et attends. Ça télécharge le framework, donc compte quelques minutes.
7. Quand c'est fini, clique sur **Save & Run Server**.

Voilà. txAdmin a déjà mis ta license key, la base de données et ton propre compte en admin dans la config. Les tables de la base se créent toutes seules au premier démarrage du serveur.

Passe à **Après le premier démarrage** plus bas.

**Optionnel : la map.** La map n'est pas incluse. Télécharge-la sur https://github.com/Arcainex/The-Apocalypse-Project, mets le dossier `[the_apocalypse_project]` dans `resources/[map]`, puis ouvre `server.cfg` et retire le `##` devant la ligne `ensure [the_apocalypse_project]`.

---

## B - Installation manuelle

### 1. Artifacts et txAdmin

Fais les étapes 1 et 2 de la partie A.

### 2. Récupère les fichiers

1. Télécharge BS19 sur https://github.com/Arcainex/bs19 (bouton vert **Code** > **Download ZIP**).
2. Crée un dossier pour les données du serveur, par exemple `C:\FXServer\beyondsurvival`, et extrais le zip dedans. Tu dois y voir `resources` et `server.cfg`.
3. Télécharge oxmysql sur https://github.com/overextended/oxmysql/releases (le fichier `oxmysql.zip`) et extrais-le dans le dossier `resources`, pour avoir `resources\oxmysql`.

### 3. Crée la base de données

1. Ouvre **HeidiSQL** (livré avec MariaDB) et connecte-toi avec l'utilisateur `root` et ton mot de passe root.
2. Clic droit sur la connexion -> Create new -> Database. Nomme-la `beyondsurvival`, collation `utf8mb4_unicode_ci`.
3. Laisse-la vide. BeyondSurvival crée toutes les tables au premier démarrage.

### 4. Édite la config

1. Ouvre `server.cfg` avec le Bloc-notes.
2. Mets ta license key dans la ligne `sv_licenseKey`, à la place de `CHANGEME`.
3. Dans la ligne `mysql_connection_string`, remplace `CHANGEME_USER` par `root` et `CHANGEME_PASSWORD` par ton mot de passe root.
4. Tu veux ton propre nom de serveur ? Change les lignes `sv_hostname` et `sv_projectName`.
5. Ajoute-toi en admin (voir **Mettre quelqu'un admin** plus bas).
6. Ne partage `server.cfg` avec personne après ça, il contient ta clé et ton mot de passe.

### 5. Branche txAdmin dessus

1. Dans l'assistant de txAdmin, choisis **Existing Server Data** et sélectionne ton dossier (`C:\FXServer\beyondsurvival`).
2. Sélectionne `server.cfg` quand il demande le fichier de config et démarre le serveur.
3. Dans txAdmin, va dans **Settings -> FXServer** et vérifie que **OneSync** est sur **On**.

---

## Après le premier démarrage

- Garde un oeil sur la console. Le premier boot est plus long parce que les tables de la base se créent et que le serveur met ses fichiers en cache.
- Ouvre FiveM, appuie sur F8 et tape `connect localhost` (ou l'IP de ton VPS).
- Crée ton personnage et t'es dedans.

## Mettre quelqu'un admin

Les admins ont le menu de config F1, le menu admin, /atlas et les commandes de debug.

1. Fais venir le joueur une fois.
2. Dans txAdmin, ouvre **Players**, clique sur le joueur et copie la ligne qui commence par `license:`.
3. Ouvre `server.cfg`, va tout en bas et ajoute :
   ```
   add_principal identifier.license:PASTE_IT_HERE group.superadmin
   ```
   Mets `group.admin` au lieu de `group.superadmin` pour le staff normal.
4. Redémarre le serveur.

Si t'as utilisé la recipe, ton compte est déjà là en `group.admin`. Change ce mot en `group.superadmin` si tu veux les droits complets de proprio.

## Changer les réglages

- La plupart des trucs se changent en jeu avec **F1** (admins seulement). Le mode Simple a les réglages courants (nombre de zombies, distance de spawn, faim, loot...). Le mode Advanced montre tout.
- Chaque resource a aussi un dossier `config` avec des réglages commentés si tu préfères éditer les fichiers.

## Des problèmes ?

| Ce que tu vois | Quoi faire |
|---|---|
| `Could not connect to database` | Mauvais user/mot de passe dans `server.cfg`, ou MariaDB ne tourne pas. |
| `License key invalid` | Recopie la clé depuis portal.cfx.re, sans espaces. |
| Le serveur n'apparaît pas dans la liste | Ouvre les ports 30120 TCP et UDP dans ton routeur/pare-feu. |
| Les joueurs restent bloqués au chargement | Vérifie que OneSync est On et que la build du jeu est la 3095. |
| Les zombies qui rampent glissent | `nutria_crawl_anims` doit démarrer avant `bs_zombies` dans `server.cfg`. |

Toujours bloqué ? Viens sur notre Discord (lien sur https://bs19.org) et poste les lignes rouges de la console.
