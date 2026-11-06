fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_fpdebug'
author 'BeyondSurvival'
description 'BeyondSurvival - FightParkDebug menu (admin only): fighting and parkour test tools.'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_util.lua',
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_locale.lua',
}

client_scripts { 'client/cl_main.lua' }
server_scripts { 'server/sv_main.lua' }

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js',
    'locales/*.lua',
}

dependencies { 'bs_core' }
