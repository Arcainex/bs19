fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_esx_bridge'
author 'BeyondSurvival'
description 'Compatibility shim - lets ESX-authored scripts run against BeyondSurvival'
version '0.1.0'
provide 'es_extended'

-- Start this resource only on standalone BS19 servers. It replaces the
-- es_extended dependency name for ESX scripts; never run it beside ESX.

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

-- Also usable from other resources via shared_scripts { '@bs_esx_bridge/shared/sh_esx.lua' }
files {
    'shared/sh_esx.lua',
    'imports.lua',
}

dependencies {
    'bs_core',
}
