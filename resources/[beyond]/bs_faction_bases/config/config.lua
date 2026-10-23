FactionBases = {}
FactionBases.Settings = {
    -- Flag radius comes from bs_building (flagRadius, F1). Two flags may not overlap: centres at least both radii apart.
    safeZonePadding = 60.0,  -- metres kept clear around town safezones (traders live inside them)
    maxSafezones = 1,        -- player factions: one hidden safezone flag (main base)
    maxOutposts = 2,         -- player factions: outposts (bs_building passes its F1 value)
    vanillaOutposts = 1,     -- vanilla factions: one outpost, placed by the leader
    reclaimSeconds = 900,
    flagItem = 'faction_flag',          -- outpost flag kit
    safezoneFlagItem = 'safezone_flag', -- safezone flag
    flagModel = 'prop_flag_us',
    placementDistance = 6.0,
    edgeMarker = true,       -- members see a ring at the safezone edge
}
FactionBases.DefaultRoles = {
    leader = { label='Leader', build=true, deposit=true, withdraw=true, manage=true, reclaim=true },
    officer = { label='Officer', build=true, deposit=true, withdraw=false, manage=false, reclaim=true },
    builder = { label='Builder', build=true, deposit=true, withdraw=false, manage=false, reclaim=false },
    quartermaster = { label='Quartermaster', build=false, deposit=true, withdraw=true, manage=false, reclaim=false },
    member = { label='Member', build=true, deposit=true, withdraw=false, manage=false, reclaim=false },
}
-- Sanctions (sv_sanctions.lua). Ranks: owner = Leader, officer = Vice Leader, member = Member. Issuers: admins (bs.admin ace), the Leader, and ranks with the `sanction` permission (Vice Leader by default).
-- effects: xp_penalty=N, drop_penalty=N, build_lock, bank_lock, leave_lock, mute_faction_chat, no_squad, rep_freeze, rep_penalty=N, fine=N (cash to faction treasury), jail (minutes of online time, capped by jailMax)
-- Minutes are clamped to [min,max]; default is used when none is given.
FactionBases.SanctionTiers = {
    { id='minor',    label='Minor',    color='#c9b37e' },
    { id='moderate', label='Moderate', color='#d08a3a' },
    { id='severe',   label='Severe',   color='#b5532b' },
    { id='critical', label='Critical', color='#8e2a1f' },
}
FactionBases.SanctionTemplates = {
    { id='minor_warning', tier='minor', label='Formal warning', effects={ xp_penalty=5, drop_penalty=5 }, min=15, max=120, default=30 },
    { id='minor_mute', tier='minor', label='Radio silence', effects={ mute_faction_chat=true }, min=10, max=240, default=30 },
    { id='minor_cell', tier='minor', label='Cool-off cell', effects={ jail=true }, min=2, max=10, default=5 },
    { id='mod_probation', tier='moderate', label='Probation', effects={ xp_penalty=10, drop_penalty=10, rep_freeze=true, no_squad=true }, min=60, max=720, default=120 },
    { id='mod_jail', tier='moderate', label='Detention', effects={ jail=true, fine=250 }, min=5, max=30, default=10 },
    { id='mod_tools', tier='moderate', label='Tools confiscated', effects={ build_lock=true, bank_lock=true }, min=60, max=1440, default=240 },
    { id='sev_disgrace', tier='severe', label='Disgrace', effects={ xp_penalty=25, drop_penalty=25, rep_penalty=100, rep_freeze=true, no_squad=true, leave_lock=true }, min=240, max=2880, default=720 },
    { id='sev_jail', tier='severe', label='Hard labour', effects={ jail=true, fine=1000, rep_penalty=50 }, min=15, max=60, default=30 },
    { id='crit_outcast', tier='critical', label='Outcast', effects={ xp_penalty=50, drop_penalty=50, build_lock=true, bank_lock=true, leave_lock=true, no_squad=true, rep_freeze=true, mute_faction_chat=true, rep_penalty=250 }, min=1440, max=10080, default=2880 },
    { id='crit_tribunal', tier='critical', label='Tribunal sentence', effects={ jail=true, fine=2500, rep_penalty=200, xp_penalty=25, no_squad=true }, min=30, max=180, default=60, jailMax=120 },
}
FactionBases.Jail = {
    defaultRadius = 25.0,   -- metres from the jail origin an inmate may wander
    maxRadius = 150.0,
    maxCells = 24,
    globalScope = '__global', -- the admin jail
    saveEvery = 30,         -- seconds between remaining-time saves
}
-- Old effect names (bs_faction_sanctions rows, FactionSanctioned callers).
FactionBases.SanctionAliases = { xp='xp_penalty', drops='drop_penalty', build='build_lock', bank='bank_lock', leave='leave_lock', mute='mute_faction_chat', squad='no_squad' }
