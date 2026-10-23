fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'bs_faction_bases'
author 'BeyondSurvival'
description 'Faction flags, bases, permissions, reclaiming and storage'
version '1.0.0'
shared_scripts { '@bs_core/shared/sh_bridge.lua', '@bs_core/shared/sh_services.lua', 'config/config.lua' }
client_scripts { 'client/cl_main.lua', 'client/cl_jail.lua' }
server_scripts { 'server/sv_main.lua', 'server/sv_sanctions.lua' }
dependencies { 'bs_core', 'bs_factions', 'bs_interactions', 'bs_inventory', 'bs_zombies' }

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
