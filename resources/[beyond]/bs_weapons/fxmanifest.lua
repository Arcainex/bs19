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
    'config/config_cosmetics.lua',
    '@bs_inventory/config/config_items_custom_attachments.lua',
    'config/config_custom_attachments.lua',
    'config/config_stickers.lua',
    'config/config_paint.lua',
}

client_scripts {
    -- Before cl_main: defines Weapons.StartPreview/StopPreview, used by the wheel.
    'client/cl_preview.lua',
    'client/cl_main.lua',
    'client/cl_attachment_view.lua',
    'client/cl_studio.lua',
    'client/cl_inspector.lua',
    'client/cl_cosmetics.lua',
    'client/cl_sticker_atlas.lua',
    'client/cl_stickers.lua',
    'client/cl_paint.lua',
    'client/cl_holster.lua',
    'client/cl_grip.lua',
    -- Before cl_reload: defines Weapons.CheckMagazine, called on SHIFT+R.
    'client/cl_magcheck.lua',
    -- Intercepts R. Independent of the others; position is for reading order.
    'client/cl_reload.lua',
    -- After cl_holster: reads Holster.busy/Holster.stowed to tell a deliberate holster from the engine removing an empty weapon
    'client/cl_dryfire.lua',
}
server_scripts {
    'server/sv_main.lua',
    'server/sv_cosmetics.lua',
    'server/sv_stickers.lua',
    'server/sv_paint.lua',
    -- /giveammo - puts the matching box of rounds for the held weapon in your bag. Staff only.
    -- The weapon->ammo mapping is derived from the item config
    'server/sv_ammodebug.lua',
}

dependencies { 'bs_core', 'bs_attachment_prototypes', 'bs_attachment_set_02', 'bs_attachment_factory_03' }

-- live overrides from the F1 config console (bs_config); after the config files
shared_script '@bs_config/shared/apply.lua'

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }

ui_page 'html/inspect.html'
files { 'html/inspect.html', 'html/inspect.css', 'html/inspect.js' }

files { 'html/stickers/*.png' }

files { 'html/sticker-atlas.html', 'html/sticker-art.js' }

files { 'html/studio-backdrop.html', 'html/workbench-backdrop.png', 'html/game-frame.js' }

files { 'html/attachments.js', 'html/attachments.css', 'html/colour-wheel.js', 'html/fit-title.js', 'html/part-icons.js', 'html/paint.html', 'html/paint-render.js' }
