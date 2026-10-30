fx_version 'cerulean'
games { 'gta5', 'rdr3' }
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'yaca-voice'
author 'MineMalox, LuftigerLuca & C0kkie'
version '3.6.0'
repository 'https://github.com/yaca-systems/fivem-yaca-typescript'
description 'YACA Voice Integration for FiveM & RedM'

dependencies {
    '/server:27092',
    '/onesync',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/script.js',
    'config/shared.json5',
    'config/towers.json5',
    'config/room_acoustics.json5',
    'locales/*.json',
}

client_scripts {
    'dist/client.js',
    'debug.lua'
}
server_script 'dist/server.js'

provide 'saltychat'

