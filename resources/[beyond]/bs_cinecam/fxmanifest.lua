fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_cinecam'
author 'BeyondSurvival'
description 'BeyondSurvival - cinematic free camera and recording tools'
version '0.1.0'

shared_scripts {
    -- Shared scripts are per-resource includes. BS.Util and BSB are only globals inside the resource that loaded them, so list them here.
    '@bs_core/shared/sh_util.lua',
    '@bs_core/shared/sh_bridge.lua',
    'config/config_cinecam.lua',
}

client_scripts {
    -- Order matters: each file assigns into a global table the next one reads at load time.
    'client/cl_state.lua',    -- settings table + KVP persistence, nothing else
    'client/cl_lockout.lua',  -- input lockout and HUD suppression
    -- Before cl_camera, which calls CineGrade on enter/leave (convention: the owner of a global loads first).
    'client/cl_grade.lua',
    'client/cl_camera.lua',   -- the camera itself
    'client/cl_path.lua',     -- keyframes and spline playback
    'client/cl_main.lua',     -- menu, commands, NUI plumbing
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
