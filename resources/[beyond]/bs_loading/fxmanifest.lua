fx_version 'cerulean'
game 'gta5'

name 'bs_loading'
author 'BeyondSurvival'
description 'BeyondSurvival - loading screen'
version '0.1.0'

loadscreen 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/lang.js',
    'html/scale.js',
}

-- Resolve the existing core default on the server, before a client starts loading.
server_scripts {
    '@bs_core/shared/sh_locale.lua',
    'server/sv_locale.lua',
}
dependency 'bs_core'
