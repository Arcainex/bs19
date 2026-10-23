fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_radio'
author 'BeyondSurvival'
description 'BeyondSurvival - every car radio plays the same emergency broadcast, synced for all players'
version '1.0.0'

shared_scripts {
    'config/config.lua',
    '@bs_config/shared/apply.lua',
    '@bs_core/shared/sh_locale.lua',
}
client_script 'client/cl_main.lua'
server_script 'server/sv_main.lua'

ui_page 'html/index.html'
files {
    'locales/*.lua',
    'html/index.html',
    'html/audio/broadcast.ogg',
}
