fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_clothing'
author 'BeyondSurvival'
description 'BeyondSurvival - wardrobe / clothing menu'
version '4.4.8'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    'config/config.lua',
}

client_scripts { 'client/cl_main.lua' }
server_scripts { 'server/sv_editor.lua' }

ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js', 'data/clothing_rules.json' }

dependencies { 'bs_core' }
