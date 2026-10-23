fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_bodily'
author 'BeyondSurvival'
description 'Infrequent bodily needs and the N-key needs wheel'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    'config/config_bodily.lua',
}

client_scripts { 'client/cl_main.lua' }
server_scripts { 'server/sv_main.lua' }

dependencies { 'bs_core', 'bs_radial' }

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
