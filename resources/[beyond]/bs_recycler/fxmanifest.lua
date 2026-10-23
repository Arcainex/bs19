fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_recycler'
author 'BeyondSurvival'
description 'BeyondSurvival - fuel-driven recyclers at fixed spots, hand dismantle yields'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    '@bs_core/shared/sh_locale.lua',
    'config/config_recycler.lua',
    '@bs_config/shared/apply.lua',
}

client_scripts { 'client/cl_main.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/sv_main.lua' }

files { 'locales/*.lua' }

dependencies { 'bs_core', 'bs_inventory', 'bs_interactions' }
