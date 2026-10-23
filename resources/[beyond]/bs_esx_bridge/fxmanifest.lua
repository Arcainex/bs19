fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_esx_bridge'
author 'BeyondSurvival'
description 'Compatibility shim - lets ESX-authored scripts run against BeyondSurvival'
version '0.1.0'

-- Using this from a third-party ESX script: change only its import.
-- ESX = exports['es_extended']:getSharedObject()  ->  ESX = exports['bs_esx_bridge']:getSharedObject()
-- See shared/sh_esx.lua for why it is a shared_script include rather than a live object (functions don't survive exports/events).

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',   -- BSB - the transport this bridge is built on
    'shared/sh_esx.lua',
}

client_scripts {
    'client/cl_main.lua',
}

server_scripts {
    'server/sv_main.lua',
}

-- Also usable from other resources via shared_scripts { '@bs_esx_bridge/shared/sh_esx.lua' }, same pattern as bs_core's sh_bridge.lua.
files {
    'shared/sh_esx.lua',
}

exports {
    'getSharedObject',
}

dependencies {
    'bs_core',
}
