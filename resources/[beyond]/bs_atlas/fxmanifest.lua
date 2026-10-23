fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_atlas'
author 'BeyondSurvival'
description 'BeyondSurvival - the Node Atlas: a live, zoomable map of the zombie simulation'
version '1.0.0'

-- bs_atlas is its own resource rather than a bs_admin tab: it is a full-screen tool with its own NUI lifetime.

shared_scripts {
    -- BSB.Await
    -- Each resource has its own Lua state, so the shared file must be listed here or BSB is nil at the first callback
    '@bs_core/shared/sh_bridge.lua',

    -- Place names and world bounds are read from bs_zombies instead of copied
    -- The atlas draws no map tiles, so this point graph is what tells you where you are looking
    '@bs_zombies/config/config_atlas.lua',

    'config/config_atlas_ui.lua',

    '@bs_core/shared/sh_locale.lua',
}

client_scripts {
    'client/cl_atlas.lua',
}

-- One server file, one read-only job: hand the page the map calibration (nodes/calibration.json) on every open, staff-gated
-- See server/sv_atlas.lua
server_scripts {
    'server/sv_atlas.lua',
}

ui_page 'html/index.html'

files {
    'locales/*.lua',
    'html/index.html',
    'html/css/style.css',
    -- map.js must come before app.js (app.js calls AtlasMap.* on load)
    -- An unlisted script is a silent 404 in NUI and gives a blank page
    'html/js/map.js',
    'html/js/app.js',
    -- html/js/host-web.js is not listed: only the nodes HTTP handler reads it, server-side
}

-- Depends on bs_core only
-- Not bs_zombies or bs_admin: if bs_zombies is stopped the atlas should still open and say the simulation is
dependencies {
    'bs_core',
}

-- nodes is not a dependency either
-- It provides the map image and calibration; if it is stopped the atlas still opens and says the image is unavailable
