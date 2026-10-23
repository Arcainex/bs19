fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_medical'
author 'BeyondSurvival'
description 'BeyondSurvival - going down, bleeding out, injuries, infection and treatment'
version '2.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    '@bs_core/shared/sh_locale.lua',
    'config/config_medical.lua',
    'config/config_conditions.lua',
}

client_scripts {
    'client/cl_downed.lua',
    'client/cl_treat.lua',
    'client/cl_carry.lua',
    'client/cl_corpse.lua',
    'client/cl_conditions.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_corpse.lua',
    'server/sv_main.lua',
    'server/sv_conditions.lua',
}

files {
    'locales/*.lua',
}

dependencies {
    'bs_core',
}

-- live overrides from the F1 config console (bs_config); after the config files
shared_script '@bs_config/shared/apply.lua'

-- crash breadcrumbs (bs_core)
client_script '@bs_core/shared/sh_crumbs.lua'
