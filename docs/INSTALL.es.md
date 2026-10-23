# Instalar BeyondSurvival

Esta guía asume que nunca montaste un servidor de FiveM. Síguela de arriba a abajo y tendrás un servidor funcionando en unos 20 minutos.

Hay dos formas de instalar:

- **A - receta de txAdmin** (la más fácil, recomendada)
- **B - instalación manual** (si prefieres hacer cada paso tú mismo)

---

## Lo que necesitas

- Un PC con Windows o un VPS Windows/Linux. Mínimo 8 GB de RAM y 10 GB libres en disco.
- Una **cuenta de Cfx.re** y una **license key del servidor**. Consigue la key en https://portal.cfx.re -> Server Keys -> Generate.
- **MariaDB** (servidor de base de datos gratis). Bájalo de https://mariadb.org/download e instálalo con las opciones por defecto. Durante la instalación pones una **contraseña de root** - apúntala, la vas a necesitar.
- GTA V y FiveM en el PC desde el que juegas, para entrar y probar.

---

## A - Instalar con la receta de txAdmin

### 1. Descarga los artifacts del servidor

1. Ve a https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/
2. Descarga la última build **recommended** (`server.7z`).
3. Crea una carpeta, por ejemplo `C:\FXServer\server`, y extrae el 7z ahí dentro. Necesitas 7-Zip para eso (https://7-zip.org).

### 2. Arranca txAdmin

1. Abre la carpeta `server` y haz doble clic en **FXServer.exe**.
2. Se abre una ventana de consola y tu navegador abre txAdmin (si no, ve a http://localhost:40120).
3. Escribe el PIN que sale en la consola, entra con tu cuenta de Cfx.re y crea la contraseña de txAdmin.

### 3. Despliega BeyondSurvival

1. En el asistente de configuración ponle nombre a tu servidor y elige **Remote URL Template**.
2. Pega esta URL:
   ```
   https://raw.githubusercontent.com/Arcainex/bs19/main/recipe.yaml
   ```
3. Elige dónde van los datos del servidor (la ruta por defecto está bien) y dale a siguiente.
4. Cuando txAdmin pida la **license key**, pega la key de portal.cfx.re.
5. En el paso de la base de datos usa:
   - Host: `localhost`
   - Port: `3306`
   - Username: `root`
   - Password: la contraseña de root de MariaDB de antes
   - Database name: déjalo como está
6. Dale a **Run Recipe** y espera. Descarga el framework, así que dale unos minutos.
7. Cuando termine, dale a **Save & Run Server**.

Y ya está. txAdmin ya metió en la config tu license key, la base de datos y tu cuenta como admin. Las tablas de la base de datos se crean solas la primera vez que arranca el servidor.

Salta a **Después del primer arranque** más abajo.

**Opcional: el mapa.** El mapa no está incluido. Descárgalo desde https://github.com/Arcainex/The-Apocalypse-Project, mete la carpeta `[the_apocalypse_project]` dentro de `resources/[map]` y luego abre `server.cfg` y quita el `##` delante de la línea `ensure [the_apocalypse_project]`.

---

## B - Instalación manual

### 1. Artifacts y txAdmin

Haz los pasos 1 y 2 de la parte A.

### 2. Consigue los archivos

1. Descarga BS19 desde https://github.com/Arcainex/bs19 (botón verde **Code** > **Download ZIP**).
2. Crea una carpeta para los datos del servidor, por ejemplo `C:\FXServer\beyondsurvival`, y extrae el zip ahí dentro. Deberías ver `resources` y `server.cfg`.
3. Descarga oxmysql de https://github.com/overextended/oxmysql/releases (el archivo `oxmysql.zip`) y extráelo en la carpeta `resources`, para que te quede `resources\oxmysql`.

### 3. Crea la base de datos

1. Abre **HeidiSQL** (viene con MariaDB) y conéctate con el usuario `root` y tu contraseña de root.
2. Clic derecho en la conexión -> Create new -> Database. Ponle `beyondsurvival`, collation `utf8mb4_unicode_ci`.
3. Déjala vacía. BeyondSurvival crea todas las tablas en el primer arranque.

### 4. Edita la config

1. Abre `server.cfg` con el Bloc de notas.
2. Pon tu license key en la línea `sv_licenseKey`, donde dice `CHANGEME`.
3. En la línea `mysql_connection_string` cambia `CHANGEME_USER` por `root` y `CHANGEME_PASSWORD` por tu contraseña de root.
4. ¿Quieres un nombre de servidor propio? Cambia las líneas `sv_hostname` y `sv_projectName`.
5. Ponte de admin (mira **Hacer admin a alguien** más abajo).
6. No compartas `server.cfg` con nadie después de esto, tiene tu key y tu contraseña.

### 5. Apunta txAdmin a eso

1. En el asistente de txAdmin elige **Existing Server Data** y selecciona tu carpeta (`C:\FXServer\beyondsurvival`).
2. Selecciona `server.cfg` cuando pida el archivo de config y arranca el servidor.
3. En txAdmin ve a **Settings -> FXServer** y asegúrate de que **OneSync** esté en **On**.

---

## Después del primer arranque

- Mira la consola. El primer arranque tarda más porque se crean las tablas de la base de datos y el servidor cachea sus archivos.
- Abre FiveM, pulsa F8 y escribe `connect localhost` (o la IP de tu VPS).
- Crea tu personaje y listo, ya estás dentro.

## Hacer admin a alguien

Los admins tienen el menú de config con F1, el menú de admin, /atlas y los comandos de debug.

1. Haz que el jugador entre una vez.
2. En txAdmin abre **Players**, haz clic en el jugador y copia la línea que empieza por `license:`.
3. Abre `server.cfg`, ve al final y añade:
   ```
   add_principal identifier.license:PASTE_IT_HERE group.superadmin
   ```
   Usa `group.admin` en vez de `group.superadmin` para el staff normal.
4. Reinicia el servidor.

Si usaste la receta, tu cuenta ya está ahí como `group.admin`. Cambia esa palabra por `group.superadmin` si quieres derechos completos de dueño.

## Cambiar ajustes

- Casi todo se puede cambiar dentro del juego con **F1** (solo admins). El modo Simple trae lo común (cantidad de zombis, distancia de spawn, hambre, loot...). El modo Advanced lo muestra todo.
- Cada resource tiene también una carpeta `config` con ajustes comentados si prefieres editar archivos.

## ¿Problemas?

| Lo que ves | Qué hacer |
|---|---|
| `Could not connect to database` | Usuario/contraseña mal en `server.cfg`, o MariaDB no está corriendo. |
| `License key invalid` | Copia la key otra vez desde portal.cfx.re, sin espacios. |
| El servidor no sale en la lista | Abre los puertos 30120 TCP y UDP en tu router/firewall. |
| Los jugadores se quedan cargando | Revisa que OneSync esté On y que la build del juego sea la 3095. |
| Los zombis que se arrastran se deslizan | `nutria_crawl_anims` tiene que arrancar antes que `bs_zombies` en `server.cfg`. |

¿Sigues atascado? Pásate por nuestro Discord (enlace en https://bs19.org) y pega las líneas rojas de la consola.
