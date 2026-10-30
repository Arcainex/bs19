fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_economy'
author 'BeyondSurvival'
description 'BeyondSurvival - vendors, loot tables and gathering'
version '0.1.0'

shared_scripts {
    -- The callback bridge: bs_economy answers 'atm:crack', and callbacks need BSB on both sides.
    '@bs_core/shared/sh_bridge.lua',
    'config/config_economy.lua',
    'config/config_junk.lua',
}

client_scripts {
    'client/cl_main.lua',
    'client/cl_atm.lua',
}

server_scripts {
    'server/sv_main.lua',
    'server/sv_atm.lua',
}

dependencies {
    'bs_core',
}

-- live overrides from the F1 config console (bs_config); after the config files
shared_script '@bs_config/shared/apply.lua'

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
