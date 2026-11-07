fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_jobs'
author 'BeyondSurvival'
description 'BeyondSurvival - faction jobs: job board, contracts, mechanic garage, gunsmith, hunting, fishing, rebels'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    '@bs_core/shared/sh_locale.lua',
    'config/config_jobs.lua',
    'config/config_garage.lua',
    -- live overrides from the F1 config console (bs_config); after the config files
    '@bs_config/shared/apply.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_core.lua',
    'server/sv_board.lua',
    'server/sv_world.lua',
    'server/sv_garage.lua',
    'server/sv_rebels.lua',
}

client_scripts {
    'client/cl_main.lua',
    'client/cl_world.lua',
    'client/cl_garage.lua',
    'client/cl_rebels.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'locales/*.lua',
}

dependencies { 'bs_core', 'oxmysql', 'bs_inventory', 'bs_interactions', 'bs_factions' }
