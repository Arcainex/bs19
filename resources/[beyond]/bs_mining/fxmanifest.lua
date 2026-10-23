fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_mining'
author 'BeyondSurvival'
description 'BeyondSurvival - gathering: mining rock and felling timber, loudly'
version '0.1.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    'config/config_mining.lua',
}

client_scripts { 'client/cl_main.lua' }
server_scripts { 'server/sv_main.lua' }

dependencies { 'bs_core', 'bs_inventory', 'bs_interactions' }

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
