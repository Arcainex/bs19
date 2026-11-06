fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_pass'
author 'BeyondSurvival'
description 'BeyondSurvival - Wasteland Pass: free 100-tier season pass, challenges and the token slot machine'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    'config/config_pass.lua',
    -- F1 console overrides (bs_config), after the config it patches
    '@bs_config/shared/apply.lua',
    '@bs_core/shared/sh_locale.lua',
}

client_scripts { 'client/cl_main.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/sv_rewards.lua', 'server/sv_main.lua' }

ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js', 'locales/*.lua' }

dependencies { 'oxmysql', 'bs_core', 'bs_inventory' }
