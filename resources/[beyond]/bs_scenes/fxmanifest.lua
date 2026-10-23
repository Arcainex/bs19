fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_scenes'
author 'BeyondSurvival'
description 'BeyondSurvival - notes survivors leave on the world'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    'config/config_scenes.lua',
}

client_scripts { 'client/cl_main.lua' }
server_scripts { 'server/sv_main.lua' }

dependencies { 'bs_core' }

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
