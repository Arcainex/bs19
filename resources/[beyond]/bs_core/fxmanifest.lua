fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_core'
author 'BeyondSurvival'
description 'BeyondSurvival - standalone RPG / zombie survival framework core'
version '0.1.0'

-- Loaded on both sides. Order matters.
shared_scripts {
    'shared/sh_debug.lua',
    'shared/sh_util.lua',
    'shared/sh_events.lua',
    'shared/sh_bridge.lua',
    'config/config.lua',
    'config/config_classes.lua',
    'config/config_characters.lua',
    'config/config_needs.lua',
    'shared/sh_framework.lua',
    -- Standalone-safe; kept after sh_framework so it picks up BS.Log.
    'shared/sh_services.lua',
    -- Translations; other resources include it as @bs_core/shared/sh_locale.lua.
    'shared/sh_locale.lua',
}

client_scripts {
    'client/cl_bootstrap.lua',
    'client/cl_crumbs.lua',
    -- cl_callback.lua removed: BSB (shared/sh_bridge.lua) now covers it with BSB.RegisterClientCallback / BSB.AwaitClient.
    'client/cl_player.lua',
    'client/cl_needs.lua',
    'client/cl_outfit.lua',
    'client/cl_spawn.lua',
    'client/cl_unstick.lua',
    'client/cl_teleport.lua',   -- shared safe teleport (export SafeTeleport)
    'client/cl_streaming.lua',  -- focus watchdog + /refreshtextures
}

server_scripts {
    'server/sv_database.lua',
    'server/sv_migrations.lua',
    'server/sv_bootstrap.lua',
    -- sv_callback.lua removed; sv_characters.lua registers through BSB directly.
    'server/sv_identity.lua',
    'server/sv_player.lua',
    'server/sv_characters.lua',
    'server/sv_needs.lua',
    'server/sv_outfit.lua',
    'server/sv_rewards.lua',
    'server/sv_commands.lua',
    'server/sv_locale.lua',
}

files {
    'sql/*.sql',
    'shared/sh_bridge.lua',
    'shared/sh_crumbs.lua',
    'shared/sh_locale.lua',
    'locales/*.lua',
}

dependencies {
    'oxmysql',
}

-- live overrides from the F1 config console (bs_config); after the config files
shared_script '@bs_config/shared/apply.lua'
