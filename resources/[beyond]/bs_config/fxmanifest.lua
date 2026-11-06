fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_config'
author 'BeyondSurvival'
description 'F1 admin configuration console - live tunables, profiles, audit log'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_locale.lua',
    'config.lua',
    'shared/schema.lua',
    'shared/presets.lua',
    'shared/apply.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_main.lua',
}

client_scripts {
    'client/cl_main.lua',
}

ui_page 'html/index.html'

files {
    'locales/*.lua',
    'html/index.html',
    'html/style.css',
    'html/simple.js',
    'html/ext_crafting.js',
    'html/ext_tutorial.js',
    'html/ext_pass.js',
    'html/ext_operations.js',
    'html/ext_darkzone.js',
    'html/ext_radio.js',
    'html/ext_loot.js',
    'html/ext_radio.js',
    'html/ext_loot.js',
    'html/ext_building.js',
    'html/ext_themes.js',
    'html/img/themes/*.png',
    'html/img/themes/*.jpg',
    'html/ext_zombies.js',
    'html/app.js',
    'html/ext_selection.js',
}

dependencies { 'oxmysql' }
