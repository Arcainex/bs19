fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_zombiesfx'
author 'BeyondSurvival (assets: farusca - Sounds for Simple Zombies)'
description 'BeyondSurvival - zombie vocal audio (replaces vanilla ped pain waves)'
version '1.0.0'

-- Replaces the ped pain audio (waveload_pain_male/female.awc, npc_ringtones.awc in s_misc.rpf) with the zombie vocals from the source .oiv, so bs_zombies' PlayPain() growls change with no code change.
-- NOTE: pain waves are shared by every ped using that voice, including the player. Stop this resource to get vanilla pain back. Assets are third-party and streamed unmodified; their licence terms apply.

-- Second voice set: alt/gtav_zombie/s_misc holds the 'GTAV Zombie (Sound)' pain waves (see CREDITS.md)
-- Only one set of waveload_pain_* can be loaded at a time, because both replace the same vanilla wave banks, so they cannot be picked per zombie

files {
    'audiodirectory/s_misc/npc_ringtones.awc',
    'audiodirectory/s_misc/waveload_pain_female.awc',
    'audiodirectory/s_misc/waveload_pain_male.awc',
}

data_file 'AUDIO_WAVEPACK' 'audiodirectory/s_misc'
