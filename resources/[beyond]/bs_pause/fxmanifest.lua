fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_pause'
author 'BeyondSurvival'
description 'BeyondSurvival - ESC pause menu'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_locale.lua',
    'config/config_pause.lua',
    '@bs_config/shared/apply.lua',
}

client_scripts { 'client/cl_presets.lua', 'client/cl_main.lua' }
server_scripts { 'server/sv_main.lua' }

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'locales/*.lua',
}

dependencies { 'bs_core' }
