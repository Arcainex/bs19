fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_events'
author 'BeyondSurvival'
description 'BeyondSurvival - scheduled world events: airdrops, supply stashes, convoys, horde waves'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    'config/config_events.lua',
    -- F1 console overrides (bs_config), after the config it patches
    '@bs_config/shared/apply.lua',
}

client_scripts { 'client/cl_main.lua', 'client/cl_healthbar.lua' }
server_scripts { 'server/sv_main.lua', 'server/sv_routes.lua', 'server/sv_events.lua' }

ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js' }

dependencies { 'oxmysql', 'bs_core', 'bs_inventory', 'bs_interactions', 'bs_zombies' }

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
