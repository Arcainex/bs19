# Instalar o BeyondSurvival

Este guia assume que nunca montaste um servidor FiveM. Segue de cima a baixo e tens um servidor a funcionar em cerca de 20 minutos.

Há duas maneiras de instalar:

- **A - recipe do txAdmin** (a mais fácil, recomendada)
- **B - instalação manual** (se quiseres fazer tudo à mão)

---

## O que precisas

- Um PC Windows ou um VPS Windows/Linux. Pelo menos 8 GB de RAM e 10 GB livres em disco.
- Uma **conta Cfx.re** e uma **license key do servidor**. Tira a key em https://portal.cfx.re -> Server Keys -> Generate.
- **MariaDB** (servidor de base de dados gratuito). Descarrega em https://mariadb.org/download e instala com as opções por defeito. Durante a instalação defines uma **password de root** - anota-a, vais precisar dela.
- GTA V e FiveM no PC onde jogas, para entrares e testares.

---

## A - Instalar com a recipe do txAdmin

### 1. Descarregar os artifacts do servidor

1. Vai a https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/
2. Descarrega a build **recommended** mais recente (`server.7z`).
3. Cria uma pasta, por exemplo `C:\FXServer\server`, e extrai lá o 7z. Precisas do 7-Zip para isso (https://7-zip.org).

### 2. Arrancar o txAdmin

1. Abre a pasta `server` e faz duplo clique em **FXServer.exe**.
2. Abre-se uma janela de consola e o browser abre o txAdmin (se não abrir, vai a http://localhost:40120).
3. Escreve o PIN que aparece na consola, faz login com a tua conta Cfx.re e cria a password do txAdmin.

### 3. Instalar o BeyondSurvival

1. No assistente de configuração dá um nome ao servidor e escolhe **Remote URL Template**.
2. Cola este URL:
   ```
   https://raw.githubusercontent.com/Arcainex/bs19/main/recipe.yaml
   ```
3. Escolhe onde ficam os dados do servidor (o por defeito serve) e clica em seguinte.
4. Quando o txAdmin pedir a **license key**, cola a key do portal.cfx.re.
5. No passo da base de dados usa:
   - Host: `localhost`
   - Port: `3306`
   - Username: `root`
   - Password: a password de root do MariaDB de há bocado
   - Database name: deixa como está
6. Clica em **Run Recipe** e espera. Vai buscar a framework, por isso dá-lhe uns minutos.
7. Quando acabar, clica em **Save & Run Server**.

E pronto. O txAdmin já pôs a tua license key, a base de dados e a tua conta como admin na config. As tabelas da base de dados são criadas automaticamente na primeira vez que o servidor arranca.

Salta para **Depois do primeiro arranque** mais abaixo.

**Opcional: o mapa.** O mapa não está incluído. Descarrega-o em https://github.com/Arcainex/The-Apocalypse-Project, põe a pasta `[the_apocalypse_project]` dentro de `resources/[map]` e depois abre o `server.cfg` e tira o `##` à frente da linha `ensure [the_apocalypse_project]`.

---

## B - Instalação manual

### 1. Artifacts e txAdmin

Faz os passos 1 e 2 da parte A.

### 2. Buscar os ficheiros

1. Descarrega o BS19 em https://github.com/Arcainex/bs19 (botão verde **Code** > **Download ZIP**).
2. Cria uma pasta para os dados do servidor, por exemplo `C:\FXServer\beyondsurvival`, e extrai lá o zip. Lá dentro deves ver `resources` e `server.cfg`.
3. Descarrega o oxmysql em https://github.com/overextended/oxmysql/releases (o ficheiro `oxmysql.zip`) e extrai-o para a pasta `resources`, ficando com `resources\oxmysql`.

### 3. Criar a base de dados

1. Abre o **HeidiSQL** (vem com o MariaDB) e liga-te com o utilizador `root` e a tua password de root.
2. Clica com o botão direito na ligação -> Create new -> Database. Chama-lhe `beyondsurvival`, collation `utf8mb4_unicode_ci`.
3. Deixa-a vazia. O BeyondSurvival cria todas as tabelas no primeiro arranque.

### 4. Editar a config

1. Abre o `server.cfg` com o Bloco de Notas.
2. Mete a tua license key na linha `sv_licenseKey`, onde diz `CHANGEME`.
3. Na linha `mysql_connection_string` troca `CHANGEME_USER` por `root` e `CHANGEME_PASSWORD` pela tua password de root.
4. Queres um nome de servidor teu? Muda as linhas `sv_hostname` e `sv_projectName`.
5. Mete-te como admin (vê **Dar admin a alguém** mais abaixo).
6. Depois disto não partilhes o `server.cfg` com ninguém, tem a tua key e a tua password.

### 5. Ligar o txAdmin a isto

1. No assistente de configuração do txAdmin escolhe **Existing Server Data** e seleciona a tua pasta (`C:\FXServer\beyondsurvival`).
2. Seleciona o `server.cfg` quando pedir o ficheiro de config e arranca o servidor.
3. No txAdmin vai a **Settings -> FXServer** e confirma que o **OneSync** está em **On**.

---

## Depois do primeiro arranque

- Fica de olho na consola. O primeiro arranque demora mais porque as tabelas da base de dados são criadas e o servidor guarda os ficheiros em cache.
- Abre o FiveM, carrega em F8 e escreve `connect localhost` (ou o IP do teu VPS).
- Cria a tua personagem e já estás dentro.

## Dar admin a alguém

Os admins têm o menu de config do F1, o menu de admin, o /atlas e os comandos de debug.

1. Pede ao jogador para entrar uma vez.
2. No txAdmin abre **Players**, clica no jogador e copia a linha que começa por `license:`.
3. Abre o `server.cfg`, vai ao fim e acrescenta:
   ```
   add_principal identifier.license:PASTE_IT_HERE group.superadmin
   ```
   Usa `group.admin` em vez de `group.superadmin` para staff normal.
4. Reinicia o servidor.

Se usaste a recipe, a tua conta já lá está como `group.admin`. Muda essa palavra para `group.superadmin` se quiseres direitos totais de dono.

## Mudar definições

- A maior parte das coisas muda-se in game com o **F1** (só admins). O Simple mode tem o essencial (quantidade de zombies, distância de spawn, fome, loot...). O Advanced mode mostra tudo.
- Cada resource tem também uma pasta `config` com definições comentadas, se preferires editar ficheiros.

## Problemas?

| O que vês | O que fazer |
|---|---|
| `Could not connect to database` | Utilizador/password errados no `server.cfg`, ou o MariaDB não está a correr. |
| `License key invalid` | Copia a key outra vez do portal.cfx.re, sem espaços. |
| Servidor não aparece na lista de servidores | Abre as portas 30120 TCP e UDP no router/firewall. |
| Jogadores ficam presos a carregar | Confirma que o OneSync está On e que a build do jogo é a 3095. |
| Zombies a rastejar deslizam | O `nutria_crawl_anims` tem de arrancar antes do `bs_zombies` no `server.cfg`. |

Ainda emperrado? Passa no nosso Discord (link em https://bs19.org) e posta as linhas vermelhas da consola.
