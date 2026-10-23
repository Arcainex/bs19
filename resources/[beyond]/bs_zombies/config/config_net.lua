-- bs_zombies - networked zombies: one OneSync ped per walker, created by the server and seen identically by all players
-- 'legacy' = each client builds local copies (cl_sync spawn()), kept for rollback

Zombies = Zombies or {}

Zombies.Mode = Zombies.Mode or 'networked'

-- One mode for server and clients
do
    local function valid(m) return m == 'networked' or m == 'legacy' end
    if IsDuplicityVersion() then
        if GetResourceState('bs_config') == 'started' then
            local ok, p = pcall(function() return exports.bs_config:GetPayload() end)
            local mine = ok and type(p) == 'table' and p.bs_zombies
            if type(mine) == 'table' and valid(mine['Zombies.Mode']) then
                Zombies.Mode = mine['Zombies.Mode']
            end
        end
    else
        local ok, gm = pcall(function() return GlobalState.bsZombieMode end)
        if ok and valid(gm) then Zombies.Mode = gm end
    end
    if not valid(Zombies.Mode) then Zombies.Mode = 'networked' end
end

Zombies.Net = {
    -- Promotion: registry record to networked ped
    promoteRadius   = 260.0,
                              -- Beyond ~250m a remote client sees a low-LOD clone that catches up by running.
    demoteHysteresis = 60.0,  -- Ped removed when nobody is within radius + this.
    spawnPerTick    = 4,      -- Max server CreatePed calls per tick.
    tickMs          = 500,    -- Promotion / sync pass interval.
    cullingRadius   = 0.0,

    -- Caps
    baseCap         = 24,     -- networked walkers with one player online
    perPlayerCap    = 18,     -- added per additional online player
    hardCap         = 160,    -- never more than this, whatever else says
    perPlayerNear   = 34,     -- max networked walkers within promoteRadius of one player

    -- Server performance: measured frame time (GetGameTimer delta of a Wait(0) loop)
    perfBudgetMs    = 70.0,   -- average server frame above this scales the cap down
    perfMinFactor   = 0.35,   -- the cap never scales below this fraction

    -- Whole-server entity monitor (GetAllPeds + GetAllObjects + GetAllVehicles)
    entitySoft      = 1400,   -- above this the cap shrinks linearly
    entityHard      = 1900,   -- down to zero here; at or above it the farthest walkers are shed
    shedPerTick     = 6,      -- walkers removed per tick while over a limit

    -- Per-client FPS guard (clients report FPS every fpsReportMs)
    fpsReportMs     = 5000,
    fpsGood         = 45,     -- at or above: full perPlayerNear around this player
    fpsLow          = 25,     -- at or below: perPlayerNear * lowFpsFactor
    lowFpsFactor    = 0.5,

    -- Lifetime
    corpseSeconds   = 120,    -- networked corpse stays this long, then server deletes it
    orphanSweepMs   = 10000,  -- sweep for bsZombie peds the registry does not know
    replaceOnUnexpectedDelete = true,  -- re-create a ped deleted without a server reason (if a player is near)

    -- Background simulation density while networked. Sim.population.target is multiplied by this at load.
    simDensityScale = 0.35,

    corpseCap       = 40,     -- at most this many networked corpses at once; oldest deleted first
    grabMaxMs       = 1500,   -- the server ends every grab after this, whatever any client says

    -- Server-side chase target (sv_net_target.lua)
    target = {
        enabled          = true,
        tickMs           = 300,
        switchMargin     = 2.0,    -- a new target must be this many metres closer to steal the chase
        graceMs          = 1500,   -- keep a target this long after it stops qualifying
        nolosMs          = 2000,
        -- A hit only reveals the shooter if they are close enough to be seen anyway
        -- Beyond this, a suppressed shot from cover stays unknown. Loud shots still draw walkers through noise.
        damageChaseRange = 50.0,
    },

    -- Shedding under load (sv_net.lua)
    -- The cap must move by more than capHysteresis before walkers are shed, and the entity hard limit sheds at most once per entity census
    capHysteresis   = 4,

    debug           = false,  -- verbose server log lines
}

-- Applied once at load, networked mode only. Needs config_sim.lua loaded first (fxmanifest order).
if Zombies.Mode == 'networked' and Sim and Sim.population then
    local k = tonumber(Zombies.Net.simDensityScale) or 1.0
    if k > 0 and k ~= 1.0 then
        if type(Sim.population.target) == 'number' then
            Sim.population.target = math.max(1000, math.floor(Sim.population.target * k))
        end
        if type(Sim.population.maxCellBaseline) == 'number' then
            Sim.population.maxCellBaseline = math.max(4, math.floor(Sim.population.maxCellBaseline * k + 0.5))
        end
    end
end
