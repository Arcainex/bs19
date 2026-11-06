fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_fighting'
author 'BeyondSurvival'
description 'BeyondSurvival - freeflow hand to hand and melee combat: target assist, paired hits, counters, finishers'
version '3.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    -- Zones.FactionSafe: where the basic trainers stand
    '@bs_zombies/config/config_zones.lua',
    'config/config_fighting.lua',
    'config/config_freeflow.lua',
    'shared/sh_fighting.lua',
    -- live overrides from the F1 console, after the config they patch
    '@bs_config/shared/apply.lua',
    '@bs_core/shared/sh_locale.lua',
}

-- v3 freeflow. The v1 client files (cl_anim, cl_contact, cl_react, cl_hud, cl_combat, cl_grab, cl_trainers) stay on disk, unloaded.
client_scripts {
    'client/cl_ff_target.lua',
    'client/cl_ff_pairs.lua',
    'client/cl_ff_hud.lua',
    'client/cl_ff_combat.lua',
}

server_scripts {
    'server/sv_main.lua',
    'server/sv_missions.lua',
}

ui_page 'html/ff/index.html'
files { 'html/ff/index.html', 'html/ff/ff.css', 'html/ff/ff.js', 'locales/*.lua' }

dependencies { 'oxmysql', 'bs_core', 'bs_skills' }
