fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_building'
author 'BeyondSurvival'
description 'BeyondSurvival - player bases: snap building, tiers, power and wires, code and faction locks, storage, vending crates'
version '3.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/app.js',
    'html/style.css',
    'html/hammer.wav',
    'html/gen_loop.ogg',
    'html/pour.ogg',
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
    'client/cl_menu.lua',
    'client/cl_tools.lua',
    'client/cl_admin.lua',
    'client/cl_vending.lua',
}

server_scripts {
    'server/sv_store.lua',
    'server/sv_main.lua',
    'server/sv_power.lua',
    'server/sv_flags.lua',
    'server/sv_raids.lua',
    'server/sv_zones.lua',
    'server/sv_vending.lua',
    'server/sv_admin.lua',
}

dependencies {
    'bs_core',
    'oxmysql',
}
