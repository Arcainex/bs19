fx_version 'cerulean'
games { 'gta5' }

author 'Chadada'
description 'chadadaApocalypseCarsV1 by Chadada (2023) - MODIFIED vendored copy. Attaches scenery props to four base-game vehicles (bodhi2, dloader, flatbed, wastelander) plus a sit-on-chair interaction. Patched for stability: see PATCHES.md for every change from upstream and CREDITS.md for attribution. Not a vehicle model pack - no assets are streamed.'
version '1.0.0-bs.1'

client_scripts {
    'ap_core.lua',    -- must load first: defines ApocalypseCars.Register
    'chairsit.lua',
    'bodhi2.lua',
    'dloader.lua',
    'flatbed.lua',
    'wastelander.lua'
}
