fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_admin'
author 'BeyondSurvival'
description 'BeyondSurvival - staff menu'
version '0.1.0'

shared_scripts {
    -- BS.Util is used by this resource's client code; shared scripts are per-resource includes, so list it or it is nil
    '@bs_core/shared/sh_util.lua',
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    '@bs_core/shared/sh_locale.lua',
    'config/config_admin.lua',
    -- Clothing.Slots off tables for the wardrobe bench's strip button
    -- A shared @-include is a file include, not a dependency; config_clothing.lua tolerates Items being absent
    '@bs_inventory/config/config_clothing.lua',
}

client_scripts {
    'client/cl_noclip.lua',
    'client/cl_clothing.lua',   -- the wardrobe bench (spawn + component tuner)
    'client/cl_zspectate.lua',
    'client/cl_main.lua',
}

server_scripts {
    -- Before sv_main: sv_main assigns the staff check into BSAdminPrefs.IsStaff, so the table must exist first.
    'server/sv_prefs.lua',
    'server/sv_main.lua',
    -- After sv_main: both read the BSAdmin table it publishes.
    'server/sv_staff.lua',
    'server/sv_commands.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js',
    'html/js/staff.js',   -- Simple view, player lists
    'locales/*.lua',
}

dependencies {
    'bs_core',
    'bs_vehicles',
    -- sv_prefs.lua calls exports.oxmysql directly; bs_core's BS.DB lives in another Lua state.
    'oxmysql',
}
