fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_radial'
author 'BeyondSurvival'
description 'BeyondSurvival - the radial menu every other resource opens'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    'config/config_radial.lua',
}

client_scripts {
    'client/cl_main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js',
}

dependencies { 'bs_core' }

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
