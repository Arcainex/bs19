fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_weapons'
author 'BeyondSurvival'
description 'BeyondSurvival - weapon attachments as real items, on a wheel'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    'config/config_weapons.lua',
}

client_scripts {
    -- Before cl_main: defines Weapons.StartPreview/StopPreview, used by the wheel.
    'client/cl_preview.lua',
    'client/cl_main.lua',
    'client/cl_holster.lua',
    -- Before cl_reload: defines Weapons.CheckMagazine, called on SHIFT+R.
    'client/cl_magcheck.lua',
    -- Intercepts R. Independent of the others; position is for reading order.
    'client/cl_reload.lua',
    -- After cl_holster: reads Holster.busy/Holster.stowed to tell a deliberate holster from the engine removing an empty weapon
    'client/cl_dryfire.lua',
}
server_scripts {
    'server/sv_main.lua',
    -- /giveammo - puts the matching box of rounds for the held weapon in your bag. Staff only.
    -- The weapon->ammo mapping is derived from the item config
    'server/sv_ammodebug.lua',
}

dependencies { 'bs_core' }

-- live overrides from the F1 config console (bs_config); after the config files
shared_script '@bs_config/shared/apply.lua'

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
