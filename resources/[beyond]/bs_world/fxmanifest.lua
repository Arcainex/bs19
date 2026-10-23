fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_world'
author 'BeyondSurvival'
description 'BeyondSurvival - dead world: no traffic, no pedestrians, custom blackout'
version '0.1.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    'config/config_world.lua',
    'config/config_power.lua',
    'config/config_time.lua',
}

client_scripts {
    'client/cl_population.lua',
    'client/cl_blackout.lua',
    'client/cl_time.lua',
}

server_scripts {
    'server/sv_main.lua',
    'server/sv_time.lua',
}

dependencies { 'bs_core' }

-- live overrides from the F1 config console (bs_config); after the config files
shared_script '@bs_config/shared/apply.lua'
