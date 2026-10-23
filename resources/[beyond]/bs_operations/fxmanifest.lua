fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_operations'
author 'BeyondSurvival'
description 'BeyondSurvival - power station capture, control points and faction mission chains'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    -- Zones.FactionSafe: faction labels and the safezone the buff lights
    '@bs_zombies/config/config_zones.lua',
    'config/config_ops.lua',
    -- F1 console overrides (bs_config), after the config it patches
    '@bs_config/shared/apply.lua',
    '@bs_core/shared/sh_locale.lua',
}

client_scripts { 'client/cl_main.lua' }

server_scripts {
    'server/sv_util.lua',
    'server/sv_power.lua',
    'server/sv_points.lua',
    'server/sv_missions.lua',
    'server/sv_admin.lua',
}

ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js', 'locales/*.lua' }

dependencies { 'oxmysql', 'bs_core', 'bs_inventory', 'bs_interactions', 'bs_zombies' }
