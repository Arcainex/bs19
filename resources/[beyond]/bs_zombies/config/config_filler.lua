-- bs_zombies - hybrid population: cheap local filler walkers on top of the networked ones
-- Filler peds exist only on one client. They wander and never fight. The moment one notices the
-- player (sight, contact, noise, a shot or a swing) it is swapped for a real networked walker at
-- the same spot, so damage, loot and kills always go through the server.
-- enabled = false puts back the old behaviour exactly: no filler, no night or player scaling.

Zombies = Zombies or {}

Zombies.Filler = {
    enabled = true,

    -- Multiplies every filler target below (F1 "Filler density").
    density = 1.0,

    -- Filler walkers kept around the player, by region (regions are in config_zones.lua, Zones.Filler).
    -- Counted inside cleanupDistance. 'wilds' is everything outside a listed region.
    targets = {
        city  = 50,   -- Los Santos
        north = 25,   -- Sandy Shores, Grapeseed, Paleto, Harmony
        wilds = 0,    -- countryside keeps today's networked-only numbers
    },

    -- Fewer zombies at night: applied to the filler target and to the networked target and cap.
    nightMult = 0.7,

    -- Networked cap against total players online: full up to fullUpTo, then down to minFactor at downTo.
    playerScale = { fullUpTo = 16, downTo = 48, minFactor = 0.6 },

    -- Pool safety. The ped pool is 256 and cl_pools.lua culls at 215.
    hardCap      = 70,    -- never more filler than this on one client
    poolCeiling  = 165,   -- filler only fills the pool up to this many peds in total; above it, filler leaves first

    -- Placement
    spawnMin        = 55.0,   -- also never under Zombies.Settings.spawnDistanceMin
    spawnMax        = 165.0,
    cleanupDistance = 180.0,
    roadSnap        = 35.0,   -- a spot must be this close to a road node (streets only)
    spawnPerPass    = 2,
    passMs          = 450,
    groupSize       = { 1, 4 },   -- small knots along the pavement read as a crowd

    -- Senses (filler only checks the local player)
    contactRadius = 6.0,
    sight = { standing = 24.0, crouched = 9.0, prone = 5.0, halfAngle = 70.0 },
    sprintHear    = 14.0,   -- sprinting this close is heard
    aimPromote    = 120.0,  -- aiming at a filler walker within this promotes it before the shot lands
    noiseScale    = 1.0,    -- noise radius multiplier for filler hearing
    turnScale     = 1.8,    -- inside noise radius x this, filler turns and shuffles toward the sound
    perNoise      = 6,      -- most promotions one noise can cause; the rest walk toward it

    -- Promotion
    maxPerMinute  = 40,     -- client and server both refuse above this per player
    gapMs         = 120,    -- spacing between promotion requests (hits skip the queue)
    ackTimeoutMs  = 4000,
    swapTimeoutMs = 3000,   -- longest the filler waits for its networked twin before it is removed anyway
    fadeMs        = 300,
    refusedFadeMs = 1500,
    serverNearCap = 46,     -- networked walkers within 120 m of the promoter before promotions are refused
    capHeadroom   = 12,     -- promotions may run this far over the networked cap (far walkers are shed)
    deathExclusionRadius = 4.0,    -- no promotion and no filler kept this close to a walker that just died
    deathExclusionMs     = 20000,

    debug = false,
}
