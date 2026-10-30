fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_building'
author 'BeyondSurvival'
description 'BeyondSurvival - player bases: snap building, code and faction locks, storage, vending crates'
version '2.1.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/app.js',
    'html/studio_pointer.js',
    'html/style.css',
    'html/hammer.wav',
    'locales/*.lua',
}

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    '@bs_core/shared/sh_locale.lua',
    'config/config_building.lua',
    '@bs_config/shared/apply.lua',
}

client_scripts {
    'client/cl_world.lua',
    'client/cl_place.lua',
    'client/cl_tools.lua',
    'client/cl_admin.lua',
    'client/cl_admin_placed.lua',
    'client/cl_prop_studio.lua',
    'client/cl_vending.lua',
}

server_scripts {
    'server/sv_store.lua',
    'server/sv_main.lua',
    'server/sv_raids.lua',
    'server/sv_zones.lua',
    'server/sv_vending.lua',
    'server/sv_admin.lua',
    'server/sv_prop_studio.lua',
}

dependencies {
    'bs_core',
    'oxmysql',
}
