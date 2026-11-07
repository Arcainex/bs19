fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'alpha_z_waffenpack'
author 'Alpha-Z integration'
description 'Alpha-Z melee pack with standalone Barbed Wire Bat and Zombie Arm'
version '1.1.0'

files {
    'zombie_meta/weaponarchetypes.meta',
    'zombie_meta/weaponanimations.meta',
    'zombie_meta/pedpersonality.meta',
    'zombie_meta/weapons.meta',
    'barbed_meta/weaponarchetypes.meta',
    'barbed_meta/weaponanimations.meta',
    'barbed_meta/weapons.meta',
}
data_file 'WEAPON_METADATA_FILE' 'zombie_meta/weaponarchetypes.meta'
data_file 'WEAPON_ANIMATIONS_FILE' 'zombie_meta/weaponanimations.meta'
data_file 'PED_PERSONALITY_FILE' 'zombie_meta/pedpersonality.meta'
data_file 'WEAPONINFO_FILE' 'zombie_meta/weapons.meta'
data_file 'WEAPON_METADATA_FILE' 'barbed_meta/weaponarchetypes.meta'
data_file 'WEAPON_ANIMATIONS_FILE' 'barbed_meta/weaponanimations.meta'
data_file 'WEAPONINFO_FILE' 'barbed_meta/weapons.meta'
client_scripts {
    'cl_weaponNames.lua',
    'cl_crossbow_tuning.lua'
}

ui_page 'breath_ui/index.html'

files {
    'breath_ui/index.html',
    'breath_ui/style.css',
    'breath_ui/script.js'
}
