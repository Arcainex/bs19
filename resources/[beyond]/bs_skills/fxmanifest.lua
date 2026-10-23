fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_skills'
author 'BeyondSurvival'
description 'BeyondSurvival - skill trees, perks and the effects they actually apply'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    'config/config_skills.lua',
    -- After config_skills.lua, which owns the `Skills` table (`Skills = {}`). Loading config_abilities.lua first would lose its values and fall back to defaults silently.
    'config/config_abilities.lua',
    'config/config_recoil.lua',
    'shared/sh_skills.lua',
}

client_scripts {
    'client/cl_main.lua',
    -- After cl_main.lua (reading order; exports are resolved at call time).
    'client/cl_dodge.lua',
    'client/cl_sway.lua',
    'client/cl_recoil.lua',
    -- Last: cl_skilldebug.lua registers /skilltest, which reports on BS_SkillsDebug published by the files above. Safe to delete first if trimming.
    'client/cl_skilldebug.lua',
}

server_scripts {
    'server/sv_main.lua',
}

dependencies {
    'bs_core',
}

-- live overrides from the F1 config console (bs_config); after the config files
shared_script '@bs_config/shared/apply.lua'

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
