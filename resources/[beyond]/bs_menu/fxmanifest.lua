fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_menu'
author 'BeyondSurvival'
description 'BeyondSurvival - the pause-style hub: inventory, stats, skills, settings'
version '0.1.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    'config/config_menu.lua',
}

client_scripts { 'client/cl_main.lua' }
server_scripts { 'server/sv_main.lua' }

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/css/faction-hub.css',
    'html/js/app.js',
}

dependencies { 'bs_core' }

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
