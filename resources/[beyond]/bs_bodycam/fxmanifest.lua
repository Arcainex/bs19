fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_bodycam'
author 'BeyondSurvival'
description 'BeyondSurvival - optional chest-mounted bodycam view'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_locale.lua',
    'config/config_bodycam.lua',
    '@bs_config/shared/apply.lua',
}

client_scripts {
    'client/cl_settings.lua',
    'client/cl_main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'locales/*.lua',
}

dependencies { 'bs_core' }
