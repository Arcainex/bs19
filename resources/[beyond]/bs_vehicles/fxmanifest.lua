fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_vehicles'
author 'BeyondSurvival'
description 'BeyondSurvival - vehicles that belong to somebody, wear out, and carry things'
version '1.0.0'

shared_scripts {
    -- BS.Util is called from this resource's client code; a shared script is a per-resource include, so it has to be listed or it is a nil global
    '@bs_core/shared/sh_util.lua',
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    'config/config_vehicles.lua',
    -- Live F1 overrides (Vehicles.World etc.).
    '@bs_config/shared/apply.lua',
}

client_scripts {
    -- Order matters: cl_core defines Veh, which everything else reads.
    'client/cl_core.lua',
    'client/cl_strip.lua',
    'client/cl_parts.lua',
    'client/cl_fuel.lua',
    'client/cl_pumps.lua',
    'client/cl_stations.lua',
    'client/cl_hud.lua',
    'client/cl_cruise.lua',
    'client/cl_keys.lua',
    'client/cl_lockpick.lua',   -- replaces Keys.Hotwire from cl_keys
    'client/cl_world.lua',
    'client/cl_noambience.lua',
    'client/cl_scrap.lua',
    'client/cl_radial.lua',
    'client/cl_noradio.lua',
    'client/cl_restore.lua',
    'client/cl_target.lua',
}

server_scripts {
    -- sv_main owns the vehicle records; sv_pumps borrows two narrow globals from it, so it has to load after
    'server/sv_main.lua',
    'server/sv_pumps.lua',
    'server/sv_world.lua',
}

dependencies {
    'bs_core',
    'bs_inventory',
    'bs_interactions',
}

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }

-- pump control panel
ui_page 'html/pump.html'
files { 'html/pump.html', 'html/pump.css', 'html/pump.js', 'html/scrap.css', 'html/scrap.js' }
