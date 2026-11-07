fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'bs_factions'
author 'BeyondSurvival'
description 'BeyondSurvival faction service'
version '2.0.0'
shared_scripts { '@bs_core/shared/sh_bridge.lua', '@bs_core/shared/sh_services.lua', 'config/config_factions.lua', 'config/config_progression.lua' }
client_scripts { 'client/cl_main.lua', 'client/cl_tags.lua', 'client/cl_squad.lua' }
server_scripts { 'server/sv_service.lua', 'server/sv_tags.lua', 'server/sv_squad.lua', 'server/sv_roster.lua', 'server/sv_progression.lua', 'server/sv_admin.lua' }
ui_page 'html/tags.html'
files { 'html/tags.html', 'html/squad.css', 'html/squad.js' }
dependencies { 'bs_core' }

-- live overrides from the F1 config console (bs_config); after the config files
shared_script '@bs_config/shared/apply.lua'

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
