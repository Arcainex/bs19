fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_tutorial'
author 'BeyondSurvival'
description 'BeyondSurvival - first-join faction picker, guided tutorial and first mission'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_locale.lua',
    'config/config_tutorial.lua',
    '@bs_config/shared/apply.lua',
}

client_scripts { 'client/cl_picker.lua', 'client/cl_main.lua' }
server_scripts { 'server/sv_main.lua', 'server/sv_admin.lua' }

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'locales/*.lua',
}

dependencies { 'bs_core' }
