-- bs_zombies - gait enforcement: every zombie gets the drunk walk

local A = function() return Zombies.Anims or {} end

local function isDrunk(set) return type(set) == 'string' and set:find('drunk', 1, true) ~= nil end

local function pickFor(ped, seed)
    local a = A()
    local list = a.shambleSet or { a.shamble }
    if not IsPedMale(ped) and type(a.femaleShambleSet) == 'table' and #a.femaleShambleSet > 0 then
        list = a.femaleShambleSet
    end
    local s = list[(math.floor(tonumber(seed) or 0) % math.max(1, #list)) + 1] or a.shamble
    return isDrunk(s) and s or 'move_m@drunk@verydrunk'
end

local function sameHash(a, b)
    if type(a) ~= 'number' or type(b) ~= 'number' then return false end
    return (a & 0xFFFFFFFF) == (b & 0xFFFFFFFF)
end

Zed = Zed or {}
Zed.gaitEnforced = 0

-- Cooldown: if the clipset hash briefly differs
local applied = {}
local drunkFlagged = {}

local function enforce(ped, id, st)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) or IsPedRagdoll(ped) or IsPedGettingUp(ped) then return end
    if st and (st.bsZombieDead or st.zCrawl) then return end
    local entry = Zed.live and id and Zed.live[id]
    if entry and (entry.crippled or entry.dying or (entry.def and entry.def.noClipset)) then return end

    local set = st and st.zGait
    if not isDrunk(set) then set = (entry and isDrunk(entry.gait) and entry.gait) or pickFor(ped, id or ped) end

    if not HasAnimSetLoaded(set) then RequestAnimSet(set); return end

    local networked = NetworkGetEntityIsNetworked(ped)
    local owned = (not networked) or NetworkHasControlOfEntity(ped)
    if owned and IsPedUsingActionMode(ped) then SetPedUsingActionMode(ped, false, -1, 'DEFAULT_ACTION') end

    -- Flag the ped itself as drunk?
    if owned and (Zombies.Settings or {}).drunkFlag == true and not drunkFlagged[ped] then
        pcall(SetPedConfigFlag, ped, 100, true)
        pcall(SetPedIsDrunk, ped, true)
        drunkFlagged[ped] = true
    end

    local ok, cur = pcall(GetPedMovementClipset, ped)
    if ok and sameHash(cur, GetHashKey(set)) then return end

    local last = applied[ped]
    if last and last.set == GetHashKey(set) and GetGameTimer() - last.at < 4000 then return end
    applied[ped] = { set = GetHashKey(set), at = GetGameTimer() }

    if owned then
        ResetPedStrafeClipset(ped)
        ResetPedWeaponMovementClipset(ped)
    end
    SetPedMovementClipset(ped, set, 0.25)
    if entry then entry.gait, entry.appliedGait = set, set; entry.gaitFixes = (entry.gaitFixes or 0) + 1 end
    Zed.gaitEnforced = Zed.gaitEnforced + 1
end

CreateThread(function()
    while true do
        Wait(250)
        if (Zombies.Settings or {}).enforceDrunkWalk ~= false then
            local seen = {}
            local ok, pool = pcall(GetGamePool, 'CPed')
            if ok and type(pool) == 'table' then
                for _, ped in ipairs(pool) do
                    if NetworkGetEntityIsNetworked(ped) and not IsPedAPlayer(ped) then
                        local okS, st = pcall(function() return Entity(ped).state end)
                        local id = okS and st and st.bsZombie
                        -- Faction NPCs keep their own gait.
                        if id ~= nil and not st.fnpc and not st.bsFnpc and not st.fnpc_o then
                            seen[ped] = true
                            enforce(ped, tonumber(id), st)
                        end
                    end
                end
            end
            -- Local (legacy-mode) walkers carry no bags; Zed.owned knows them.
            for ped in pairs(applied) do
                if not DoesEntityExist(ped) then applied[ped] = nil; drunkFlagged[ped] = nil end
            end
            for ped, id in pairs(Zed.owned or {}) do
                if not seen[ped] and not NetworkGetEntityIsNetworked(ped) then enforce(ped, id, nil) end
            end
        end
    end
end)
