fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'alpha_z_tester'
author 'Alpha-Z'
description 'Separate ACE-gated QA tester menu (F4); no staff permissions'
version '1.0.1'

shared_scripts { 'config/config.lua' }
server_scripts { 'server/main.lua' }
client_scripts { 'client/main.lua' }
ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js' }
dependencies { 'bs_core', 'bs_inventory' }
