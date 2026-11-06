fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'bs_survivor'
author 'BeyondSurvival'
description 'Survivor condition and character record'
version '1.0.0'
shared_scripts { '@bs_core/shared/sh_bridge.lua', '@bs_core/shared/sh_locale.lua' }
client_script 'client.lua'
server_script 'server.lua'
ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js', 'locales/*.lua' }
dependencies { 'bs_core', 'oxmysql' }
