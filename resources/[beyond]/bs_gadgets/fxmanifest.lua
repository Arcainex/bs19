fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_gadgets'
author 'BeyondSurvival'
description 'BeyondSurvival - deployable gadgets (2 slots): drone, turret, medic beacon, decoy, riot shield'
version '1.0.0'

shared_scripts {
    'config/config_gadgets.lua',
    '@bs_config/shared/apply.lua',   -- F1 config console overrides, live
}

client_scripts {
    -- Loot container models, so the drone marks the same props you can search.
    '@bs_interactions/config/config_containers.lua',
    'client/cl_main.lua',
    'client/cl_drone.lua',
    'client/cl_deploy.lua',
    'client/cl_shield.lua',
    'client/cl_charge.lua',
}

server_scripts {
    'server/sv_main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
}

dependencies { 'bs_core', 'bs_inventory' }

-- crash breadcrumbs (bs_core)
client_script '@bs_core/shared/sh_crumbs.lua'

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
