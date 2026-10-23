fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_interactions'
author 'BeyondSurvival'
description 'BeyondSurvival - dot targeting, world interactions, searchable containers'
version '0.2.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    -- BS.Util.ModelOf is used by the scan. A resource that calls into BS.Util
    -- must ship sh_util itself: every resource gets its own Lua state, so an
    -- @-prefixed shared script is a per-resource include and not a global.
    -- bs_factions had exactly this bug with BS.Log and it presented as a nil
    -- global at runtime with nothing wrong at load time.
    '@bs_core/shared/sh_util.lua',
    'config/config.lua',
    'config/config_containers.lua',
}

client_scripts {
    'client/cl_target.lua',
    'client/cl_registry.lua',
    'client/cl_search.lua',
}

server_scripts { 'server/sv_main.lua' }

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js',
}

dependencies { 'bs_core' }

-- live overrides from the F1 config console (bs_config); after the config files
shared_script '@bs_config/shared/apply.lua'

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
