fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_crafting'
author 'BeyondSurvival'
description 'BeyondSurvival - crafting queues, stations, cooking, gathering, farming and traps'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    '@bs_core/shared/sh_locale.lua',
    'config/config_crafting.lua',
    'config/config_recipes.lua',
    '@bs_config/shared/apply.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_main.lua',
    'server/sv_world.lua',
    'server/sv_admin.lua',
}

client_scripts {
    'client/cl_main.lua',
    'client/cl_world.lua',
}

files { 'locales/*.lua' }

dependencies { 'bs_core', 'bs_inventory', 'bs_interactions' }

client_script '@bs_core/shared/sh_crumbs.lua'
