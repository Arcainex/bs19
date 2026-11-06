fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_parkour'
author 'BeyondSurvival'
description 'BeyondSurvival - parkour skill: vaults, climbs, wall runs, slides, rolls, ledges, trainers and trials'
version '3.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    'config/config_parkour.lua',
    -- F1 overrides patch Parkour.* after the config is loaded
    '@bs_config/shared/apply.lua',
    '@bs_core/shared/sh_locale.lua',
}

-- v3. The v1 files (cl_detect, cl_moves, cl_main) stay in the folder but are no longer loaded.
client_scripts {
    'client/cl_pk3_detect.lua',
    'client/cl_pk3_moves.lua',
    'client/cl_pk3_main.lua',
    'client/cl_pk3_measure.lua',
    'client/cl_trainers.lua',
}

server_scripts {
    'server/sv_main.lua',
    'server/sv_missions.lua',
}

files { 'locales/*.lua' }

dependencies { 'bs_core', 'bs_skills' }
