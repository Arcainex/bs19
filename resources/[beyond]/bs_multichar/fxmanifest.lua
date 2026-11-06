fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_multichar'
author 'BeyondSurvival'
description 'BeyondSurvival - character select and creator with a live 3D preview'
version '0.1.0'

shared_scripts {
    -- Runs inside this resource's Lua state, see the header of sh_bridge.lua.
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    'config/config_multichar.lua',
    '@bs_config/shared/apply.lua',
    -- config/config_presets.lua is not loaded (presets were removed from the creator). bs_inventory's
}

client_scripts {
    'client/cl_scene.lua',
    'client/cl_selection_set.lua',
    'client/cl_main.lua',
    'client/cl_edit.lua',
}

server_scripts {
    'server/sv_main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js',
}

dependencies {
    'bs_core',
}

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
