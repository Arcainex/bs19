fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_drugs'
author 'BeyondSurvival'
description 'BeyondSurvival - drugs, cigarettes, addiction and withdrawal'
version '0.1.0'

shared_scripts { 'config/config.lua' }
client_scripts { 'client/cl_anim.lua', 'client/cl_main.lua', 'client/cl_fx.lua' }

ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js' }
server_scripts { 'server/sv_main.lua' }

dependencies { 'bs_core', 'bs_inventory' }

-- live overrides from the F1 config console (bs_config); after the config files
shared_script '@bs_config/shared/apply.lua'

-- crash breadcrumbs (bs_core)
client_script '@bs_core/shared/sh_crumbs.lua'

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
