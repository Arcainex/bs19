fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_personal_storage'
author 'BeyondSurvival'
description 'Character-bound personal storage'
version '1.0.0'

shared_script 'config/config.lua'
client_script 'client/cl_main.lua'
server_script 'server/sv_main.lua'

dependencies {
    'bs_core',
    'bs_inventory'
}
