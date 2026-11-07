fx_version 'cerulean'
game 'gta5'
lua54 'yes'
ui_page 'html/index.html'
shared_script 'config.lua'
client_script 'client/main.lua'
server_script 'server/main.lua'
shared_script '@bs_core/shared/sh_bridge.lua'
dependency 'bs_core'
dependency 'oxmysql'
dependency 'bs_inventory'
files { 'html/img/book_themes/*.png',
    'html/index.html', 'html/index.css', 'html/index.js', 'html/img/**/*.png' }
