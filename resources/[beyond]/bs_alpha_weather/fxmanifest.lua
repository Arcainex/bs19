fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'bs_alpha_weather'
author 'BeyondSurvival / Alpha-Z'
description 'Alpha-Z V23: server-synced shelter warnings every 2min, 10s each'
version '1.23.0'

ui_page 'html/alpha_warning_v23.html'
files {
    'html/index.html',
    'html/alpha_warning_v23.html',
    'html/sounds/sirene.mp3'
}

client_script 'client/cl_main.lua'
server_script 'server/sv_main.lua'
