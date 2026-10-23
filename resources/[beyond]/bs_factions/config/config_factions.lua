-- bs_factions - four RP-only factions.
-- Joining or standing with one has no gameplay effect (no damage, speed, loot
-- or XP). Reputation buys titles, cosmetic clothing and exclusive emotes. VIP
-- may speed reputation gain but never grant a gameplay advantage.
-- Unlocks are kept forever, even after leaving the faction.

Factions = {}

Factions.Settings = {
    -- Hard ceiling. Rewards past this are not credited.
    maxReputation      = 20000,  -- tiers below are about 3x harder than before

    -- Seconds before a player who left a vanilla faction can join another vanilla faction.
    vanillaJoinCooldown = 86400,

    joinCommand   = 'joinfaction',
    leaveCommand  = 'leavefaction',
    statusCommand = 'faction',
    listCommand   = 'factions',
}

-- The factions. `unlocks` is an ordered list of { rep, type, id, label }.
-- `type` ('title' | 'clothing' | 'emote') is informational; bs_factions only
-- tracks whether an id was earned, not what it means to the owning resource.
Factions.List = {
    military = {
        id     = 'military',
        label  = 'Military',
        short  = 'MIL',
        colour = { r = 107, g = 122, b = 74 },
        blurb  = 'What is left of the army. Order, discipline and firepower.',
        unlocks = {
            { rep = 300,   type = 'title', id = 'military_1', label = 'Private' },
            { rep = 4500,  type = 'title', id = 'military_2', label = 'Sergeant' },
            { rep = 8500,  type = 'emote', id = 'military_salute', label = 'Salute' },
            { rep = 15000, type = 'title', id = 'military_3', label = 'Commander' },
        },
    },
    rebels = {
        id     = 'rebels',
        label  = 'Rebels',
        short  = 'REB',
        colour = { r = 160, g = 60, b = 50 },
        blurb  = 'Took what the old world left behind and never gave it back.',
        unlocks = {
            { rep = 300,   type = 'title', id = 'rebels_1', label = 'Recruit' },
            { rep = 4500,  type = 'title', id = 'rebels_2', label = 'Raider' },
            { rep = 8500,  type = 'emote', id = 'rebels_salute', label = 'Salute' },
            { rep = 15000, type = 'title', id = 'rebels_3', label = 'Warlord' },
        },
    },
    civilians = {
        id     = 'civilians',
        label  = 'Civilians',
        short  = 'CIV',
        colour = { r = 170, g = 160, b = 130 },
        blurb  = 'Ordinary people trying to rebuild something worth living in.',
        unlocks = {
            { rep = 300,   type = 'title', id = 'civilians_1', label = 'Survivor' },
            { rep = 4500,  type = 'title', id = 'civilians_2', label = 'Settler' },
            { rep = 8500,  type = 'emote', id = 'civilians_salute', label = 'Salute' },
            { rep = 15000, type = 'title', id = 'civilians_3', label = 'Elder' },
        },
    },
    bikers = {
        id     = 'bikers',
        label  = 'Bikers',
        short  = 'BKR',
        colour = { r = 96, g = 110, b = 130 },
        blurb  = 'Road crews that keep the highways open and the engines running.',
        unlocks = {
            { rep = 300,   type = 'title', id = 'bikers_1', label = 'Prospect' },
            { rep = 4500,  type = 'title', id = 'bikers_2', label = 'Patched' },
            { rep = 8500,  type = 'emote', id = 'bikers_salute', label = 'Salute' },
            { rep = 15000, type = 'title', id = 'bikers_3', label = 'Road Captain' },
        },
    },
}

-- Ordered id list, for /factions and validation.
Factions.Order = { 'military', 'rebels', 'civilians', 'bikers' }

-- Starting ranks for the vanilla factions, top to bottom. 'owner' is always the Leader (every permission).
-- `base` picks the default permission set (officer or member), `perms` overrides single ones.
-- Keep the ids 'officer' and 'member': existing members already hold them. Leaders can change all of this
-- in the hub (RANKS tab); this only applies the first time a faction is read.
-- Permissions: deposit withdraw invite kick promote sanction build demolish storage jail squad_manage skills raid jobs
Factions.DefaultRanks = {
    military = {
        { id = 'owner',   label = 'Commander' },
        { id = 'officer', label = 'Sergeant' },
        { id = 'veteran', label = 'Corporal', base = 'member', perms = { invite = true, squad_manage = true } },
        { id = 'member',  label = 'Private' },
    },
    rebels = {
        { id = 'owner',   label = 'Warlord' },
        { id = 'officer', label = 'Lieutenant' },
        { id = 'veteran', label = 'Raider', base = 'member', perms = { invite = true, raid = true } },
        { id = 'member',  label = 'Recruit' },
    },
    civilians = {
        { id = 'owner',   label = 'Mayor' },
        { id = 'officer', label = 'Councillor' },
        { id = 'veteran', label = 'Settler', base = 'member', perms = { invite = true, demolish = true } },
        { id = 'member',  label = 'Newcomer' },
    },
    bikers = {
        { id = 'owner',   label = 'President' },
        { id = 'officer', label = 'Road Captain' },
        { id = 'veteran', label = 'Patched', base = 'member', perms = { invite = true, squad_manage = true } },
        { id = 'member',  label = 'Prospect' },
    },
}

-- Old faction ids and what they became. Members and progress are moved on boot.
Factions.Renamed = { militia = 'military', mechanics = 'bikers' }
Factions.Removed = { 'medics', 'farmers' }

-- Factions have nothing to do with player classes: a medic, mechanic or engineer can join any
-- of them. Every rewarded action below gives reputation to the player's OWN faction.
-- Keys are the action ids in bs_core's Config.Rewards.
Factions.ActionRewards = {
    zombie_kill          = { rep = 2 },
    zombie_kill_headshot = { rep = 3 },
    zombie_kill_brute    = { rep = 15 },
    horde_cleared        = { rep = 40 },
    player_revived       = { rep = 15 },
    wound_treated        = { rep = 6 },
    vehicle_repaired     = { rep = 10 },
    vehicle_hotwired     = { rep = 8 },
    vehicle_scrapped     = { rep = 5 },
    item_crafted         = { rep = 4 },
    resource_gathered    = { rep = 3 },
}

function Factions.Get(id)
    return Factions.List[tostring(id or '')]
end

function Factions.IsValid(id)
    return Factions.List[tostring(id or '')] ~= nil
end

-- Name tags over your own people. Opt-in per player from the Faction menu. Only
-- squad and faction mates are sent by the server, and tags hide behind walls.
Factions.Tags = {
    range         = 50.0,   -- default metres (player slider bs_tags_range, 10..150)
    rangeMin      = 10, rangeMax = 150,
    fadeStart     = 0.5,    -- fraction of the player's range where fading starts
    safeRadius    = 160.0,  -- server: max distance of strangers returned in a safe zone
    safeRefreshMs = 2000,   -- faster list refresh while inside a safe zone
    minScale      = 0.62,   -- how small a tag gets at the edge of range
    headOffset    = 0.35,   -- metres above the head bone
    refreshMs     = 5000,   -- how often the mate list is re-requested from the server
    sightMs       = 250,    -- how often line of sight is re-checked
    frameMs       = 0,      -- 0 = position every frame while tags are on screen
    rankLabels    = { owner = 'LEADER', officer = 'OFFICER', member = 'MEMBER' },
    squadRankLabels = { ['1'] = 'LEAD', ['2'] = 'SECOND', ['3'] = 'MEMBER' },
    colours = {
        faction = '#e08c46',  -- amber, same accent as the hub
        squad   = '#7fd4a2',  -- the hub's good green, so squad reads apart
        text    = '#f0ebdd',  -- bone
        muted   = '#a8a293',  -- dust
        down    = '#c0564a',
        neutral = '#c9c2b0',  -- safe-zone strangers
    },
}

-- Squads (bs_factions/server/sv_squad.lua, client/cl_squad.lua)
Factions.Squad = {
    maxSize        = 5,      -- members including the leader
    maxRanks       = 6,
    nameMax        = 24,
    inviteSeconds  = 60,     -- how long an invitation stays answerable
    inviteDistance = 25.0,   -- metres, checked server-side
    revalidateMs   = 30000,  -- re-check faction membership of online members (offline members are never touched)
    uiKey          = 'F3',   -- squad console keybind (/squadconsole), players can rebind it
    uiCommand      = 'squadconsole', -- fresh name: FiveM keeps old binds per command, and 'squad'/'squadmenu' were once on F2
    defaultRanks   = { { id = 1, label = 'Lead' }, { id = 2, label = 'Second' }, { id = 3, label = 'Member' } },
    blip = { sprite = 1, colour = 2, scale = 0.85, refreshMs = 1000 },
}
