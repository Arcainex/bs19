fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'bs_vehicle_crafting'
author 'BeyondSurvival'
description 'Mechanic-only vehicle parts storage and vehicle assembly'
version '1.0.0'
shared_scripts { '@bs_core/shared/sh_bridge.lua', 'config/config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/sv_main.lua' }
client_scripts { 'client/cl_main.lua' }
ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js' }
dependencies { 'bs_core', 'bs_jobs', 'bs_inventory', 'bs_vehicles', 'bs_interactions', 'oxmysql' }
