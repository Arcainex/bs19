fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nodes'
author 'BeyondSurvival'
description 'BeyondSurvival - the sector map, served as a web panel'
version '1.0.0'

-- Why the atlas is its own web panel and not a txAdmin tab: txAdmin has no plugin API and updates itself, which would remove any patch. A resource can serve its own HTTP endpoint instead:
-- http://<server>:<port>/nodes?key=<token>

server_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_locale.lua',
    'server/sv_locale.lua',
    -- ZAtlas.bounds and ZAtlas.points (world box and place names) are read from bs_zombies, not copied, like bs_atlas's fxmanifest. Must come before sv_http.lua.
    '@bs_zombies/config/config_atlas.lua',
    'server/sv_http.lua',
}

-- html/img/map.png must stay listed: the in-game /atlas loads it as nui://nodes/html/img/map.png, and files not in files{} are never sent to clients. The web panel serves it via /img/map.png.
-- html/nodes.html is no longer served and can be deleted.
files {
    'html/index.html',
    'html/nodes.html',
    'html/img/map.png',
}

dependencies {
    'bs_core',
    'bs_zombies',
}
