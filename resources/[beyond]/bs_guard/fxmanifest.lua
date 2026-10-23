fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_guard'
author 'BeyondSurvival'
description 'BeyondSurvival - anti-cheat DETECTION layer (log + alert staff only, never kicks/bans)'
version '0.1.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    'config/config_guard.lua',
    -- After the config: patches Guard.* from the active F1 (bs_config) profile.
    '@bs_config/shared/apply.lua',
    '@bs_core/shared/sh_locale.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_core.lua',      -- Flag(), DB, alerts, staff whitelist, Allow()
    'server/sv_movement.lua',  -- teleport / speed / super jump / noclip
    'server/sv_combat.lua',    -- god mode, weapons, explosions, entities, ptfx
    'server/sv_events.lua',    -- net event rate limits
    'server/sv_economy.lua',   -- money / item deltas
    'server/sv_admin.lua',     -- F10 GUARD tab callbacks
}

client_scripts {
    'client/cl_spectate.lua',
}

files {
    'locales/*.lua',
}

dependencies {
    'bs_core',
    'oxmysql',
}
