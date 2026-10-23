fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_ui'
author 'BeyondSurvival'
description 'BeyondSurvival - HUD, notifications and shared NUI shell'
version '0.1.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    'config/config_ui.lua',
}

client_scripts {
    'client/cl_nui.lua',
    'client/cl_hud.lua',
    'client/cl_levelup.lua',
    'client/cl_fieldmap.lua',
    'client/cl_notify.lua',
    'client/cl_sound.lua',
    -- Personal screen filter. Reads UI.Filters and is driven by cl_hud.lua settings; load order relative to cl_hud doesn't matter.
    'client/cl_filter.lua',
    'client/cl_partyhud.lua',
    'client/cl_announce.lua',
    'client/cl_uiscale.lua',
    'client/cl_hidehud.lua',
    'client/cl_hudmove.lua',
    -- Last, owns nothing: a watchdog that clears a leaked screen blur / NUI focus. Must load after anything that fades the blur in so its onClientResourceStop handler runs after theirs.
    'client/cl_blurguard.lua',
}

server_scripts {
    'server/sv_main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/shared/*.js',
    'html/img/*.svg',
    'html/img/weapons/*.png',
    'html/img/items/*.png',
    -- Shared inventory art is addressed through nui://bs_ui. Nested folders must be declared or CEF shows broken images.
    'html/img/xanderp/clothing/*.png',
    'html/img/xanderp/items/*.png',
    'html/img/xanderp/weapons/*.png',
    'html/sound/*.ogg',
    'html/sound/*.mp3',
    'html/sound/*.wav',
}

dependencies {
    'bs_core',
}

-- live overrides from the F1 config console (bs_config); after the config files
shared_script '@bs_config/shared/apply.lua'

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
