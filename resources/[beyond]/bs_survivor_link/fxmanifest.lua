fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'bs_survivor_link'
author 'BeyondSurvival'
description 'Two survivors, one shared story'
version '0.1.0'
shared_scripts { '@bs_core/shared/sh_bridge.lua', '@bs_core/shared/sh_locale.lua', 'config/config_link.lua', '@bs_config/shared/apply.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/sv_gear.lua', 'server/main.lua', 'server/sv_grab.lua', 'server/sv_membership.lua' }
client_scripts { 'client/cl_stealth.lua', 'client/cl_move.lua', 'client/main.lua', 'client/cl_appearance.lua', 'client/cl_target.lua', 'client/cl_status.lua', 'client/cl_downed.lua', 'client/cl_gear.lua', 'client/cl_revive.lua', 'client/cl_admin.lua' }
ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js', 'locales/*.lua' }
dependencies { 'bs_core', 'bs_inventory', 'bs_medical', 'bs_radial', 'bs_interactions' }
