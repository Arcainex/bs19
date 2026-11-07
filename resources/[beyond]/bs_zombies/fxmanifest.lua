fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_zombies'
author 'BeyondSurvival'
description 'BeyondSurvival - server-synced walkers: one list, one health pool, hosted AI, individual-zombie simulation'
version '3.0.0'

-- bs_zombies - merged manifest for the simulation layer
-- Removed: server/sv_nodes.lua

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    -- BS.Util.ModelOf, used by the pool census
    -- Each resource has its own Lua state, so an @-prefixed shared script must be listed here or the call is a nil global
    '@bs_core/shared/sh_util.lua',
    'shared/sh_policy.lua',
    'config/config_zombies.lua',
    -- Stage 3/4 streaming tunables
    -- After config_zones and config_zombies: it reads Zones.Safe and Zombies.Settings.safeZonePadding at load
    'config/config_streaming.lua',
    'config/config_sectors.lua',
    'config/config_noise.lua',
    'config/config_zones.lua',
    -- Atlas point graph
    -- The far field reads ZAtlas.points as a density map (a cell near many high-d points is built-up) and
    'config/config_atlas.lua',
    -- Simulation tunables, shared: sv_sim*.lua (server) and cl_spawner.lua (client, open-ground push) both read it
    -- After config_atlas.lua and config_streaming.lua; the spawn numbers only make sense next to Streaming.spawnMin/spawnMax
    'config/config_sim.lua',
    -- Networked-walker mode + tunables. After config_sim.lua (scales its density).
    'config/config_net.lua',
    -- Difficulty multipliers (Zombies.Difficulty). After the config files.
    'shared/sh_difficulty.lua',
}

client_scripts {
    'client/cl_sync.lua',
    -- Networked mode: adopts server-created walker peds into Zed.live. No-op in legacy.
    'client/cl_net.lua',
    'client/cl_zdebug.lua',
    'client/cl_spawner.lua',
    'client/cl_ai.lua',
    'client/cl_attack.lua',
    'client/cl_combat.lua',
    -- Damage detected from the shooter
    -- After cl_combat (reports through its hitmarker event) and after cl_sync
    'client/cl_damage.lua',
    'client/cl_execute.lua',
    'client/cl_finisher.lua',
    'client/cl_horde.lua',
    'client/cl_crawl.lua',
    -- Low-fence vault for stuck walkers (owner only). Reads Zed.live.
    'client/cl_vault.lua',
    -- Drunk walk on every walker ped, entry or not. See its header.
    'client/cl_gait_enforce.lua',
    'client/cl_vehicle.lua',
    'client/cl_safezones.lua',
    -- Settings first: cl_healthbar and cl_hitmarker listen to its broadcast.
    'client/cl_options.lua',
    'client/cl_healthbar.lua',
    'client/cl_hitmarker.lua',
    -- Stance report
    -- The server's sense ladder cannot see crouch/prone (bs_emotes state machines on the client, not a networked ped flag)
    'client/cl_sim_stance.lua',
    -- Last: the pool watchdog reaches into Zed.live and the corpse table, so what it culls must exist first.
    'client/cl_pools.lua',
}

server_scripts {
    -- Difficulty: progression near a point, per-player factors.
    'server/sv_difficulty.lua',
    -- First: merges data/atlas_points.json (the /atlas survey) over ZAtlas.points before anything reads it.
    'server/sv_atlas_points.lua',
    -- Sector state first: the registry's director asks it what each square km may hold
    -- See the top of sv_sectors.lua
    'server/sv_sectors.lua',
    'server/sv_registry.lua',
    -- Point-of-interest board
    -- After sv_registry, before sv_director (which publishes to it on every accepted noise)
    'server/sv_poi.lua',
    'server/sv_director.lua',

    -- The simulation, in dependency order: sv_sim.lua - grid, individuals, promotion/demotion, migration, regrowth, herd observation
    -- First, the others read ZSim. sv_sim_senses.lua - sense ladder and noise scoring.
    'server/sv_sim.lua',
    'server/sv_sim_senses.lua',
    'server/sv_sim_compat.lua',
    'server/sv_sim_atlas.lua',

    -- After the simulation: the planner uses ZNodes.Nearby / ZNodes.ready, published by sv_sim_compat.lua
    -- Source of candidate spawn points (simulation or plain ring)
    'server/sv_spawnsrc.lua',
    'server/sv_streaming.lua',
    -- Networked mode: promotes registry records to server-created peds. No-op in legacy.
    'server/sv_net.lua',
    -- After sv_net.lua: reads ZNet.ents and wraps ZSimSense.ReportDamage.
    'server/sv_net_target.lua',
    'server/sv_flagzones.lua',
}

dependencies {
    'bs_core',
}

-- live overrides from the F1 config console (bs_config); after the config files
shared_script '@bs_config/shared/apply.lua'

-- crash breadcrumbs (bs_core)
client_script '@bs_core/shared/sh_crumbs.lua'

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
