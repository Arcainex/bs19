fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_chat'
author 'BeyondSurvival'
description 'BeyondSurvival - the chat, replacing the stock one'
version '1.0.0'

-- Replaces the stock `chat`: remove `ensure chat` from server.cfg and add `ensure bs_chat`. Running both shows two chat boxes and doubled messages.
-- Provides chat:addMessage, chat:clear, chat:addSuggestion and chat:removeSuggestion under their original names.

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    'config/config_chat.lua',
}

client_scripts { 'client/cl_main.lua' }
server_scripts { 'server/sv_main.lua' }

ui_page 'html/index.html'

files { 'html/index.html' }

dependencies { 'bs_core' }

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
