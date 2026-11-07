fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_emotes'
author 'BeyondSurvival'
description 'BeyondSurvival - survivor actions, emotes and clothing'
version '0.2.0'

shared_scripts {
    -- BS.Util is used by this resource's client code; list the shared script or it is nil.
    '@bs_core/shared/sh_util.lua',
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    'config/config_emotes.lua',
    -- the big catalog, appended to the lists above
    'config/config_emotes_catalog.lua',
}

client_scripts {
    'client/cl_actions.lua',
    'client/cl_point.lua',
    'client/cl_prone.lua',
    -- After cl_prone: takes over /standup for both stances and reads the Prone global.
    'client/cl_crouch.lua',
    -- After cl_prone: reads the Prone global to stand down while the player is on the floor. Camera-only.
    'client/cl_lean.lua',
    'client/cl_focus.lua',
    'client/cl_noise.lua',
    -- After cl_noise: calls Noise.Make, which that file publishes as a global.
    'client/cl_vehiclenoise.lua',
    'client/cl_movement.lua',
    'client/cl_emotes.lua',
    -- AFTER cl_emotes: uses the EmoteCore global it publishes.
    'client/cl_emotemenu.lua',
    'client/cl_seats.lua',
}

ui_page 'html/index.html'
files { 'html/index.html' }

server_scripts { 'server/sv_main.lua' }

dependencies { 'bs_core' }

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
