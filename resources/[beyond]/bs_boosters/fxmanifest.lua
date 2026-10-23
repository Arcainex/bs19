fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_boosters'
author 'BeyondSurvival'
description 'BeyondSurvival - single-use personal buffs (3 slots, PvE only)'
version '0.1.0'

shared_scripts {
    'config/config_boosters.lua',
}

client_scripts {
    'client/cl_main.lua',
}

server_scripts {
    'server/sv_main.lua',
}

dependencies { 'bs_core', 'bs_inventory' }

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
