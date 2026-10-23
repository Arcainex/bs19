fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_stash'
author 'BeyondSurvival'
description 'BeyondSurvival - buried stashes: a cache only the person who dug it knows about'
version '0.1.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    'config/config_stash.lua',
}

client_scripts { 'client/cl_main.lua' }
server_scripts { 'server/sv_main.lua' }

dependencies { 'bs_core', 'bs_inventory', 'bs_interactions' }

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
