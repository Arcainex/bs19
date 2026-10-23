-- bs_zombies - walkers grab at the player with an upper-body animation

-- Crash guard: only touch peds that exist
local function pedOk(ped, allowDown)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then return false end
    if not allowDown and (IsPedRagdoll(ped) or IsPedGettingUp(ped)) then return false end
    if NetworkGetEntityIsNetworked(ped) and not NetworkHasControlOfEntity(ped) then return false end
    return true
end

local A = Zombies.Attack
local R = Zombies.Reach

-- One grab at a time on this client
local Swing = {
    active   = false,
    id       = nil,
    token    = 0,       -- increments once per grab
    deadline = 0,       -- GetGameTimer() past which this grab counts as stranded
    stage    = 'idle',  -- where it got to, for the stranded message
}

-- Godmode lives in bs_admin and works through the engine's damage pipeline
local function isGodmode()
    if GetResourceState('bs_admin') ~= 'started' then return false end
    local ok, value = pcall(function() return exports.bs_admin:IsGodmode() end)
    return ok and value == true
end

-- The attack is gated on the separate zombie-godmode toggle, not plain godmode
local function isZombieGodmoded()
    local ok, state = pcall(function() return LocalPlayer.state end)
    return ok and state and state.bsZombieGodmode == true
end

-- Animation

-- Pick a grab animation that exists and is not a punch
local Chosen = nil
local animChecked = false

local function clipIsReal(dict, clip)
    local ok, duration = pcall(GetAnimDuration, dict, clip)
    return ok and type(duration) == 'number' and duration > 0.0
end

-- True when a clip name is one this resource refuses to play on a walker
local function isForbidden(clip)
    local name = tostring(clip or ''):lower()
    for _, fragment in ipairs(A.forbiddenClipFragments or {}) do
        if name:find(tostring(fragment):lower(), 1, true) then return fragment end
    end
    return nil
end

local function ensureAnim()
    if animChecked then return Chosen ~= nil end
    animChecked = true

    -- grabAnims is the list; swingAnims is the same table under its old name, read only so an older config still starts
    for _, c in ipairs(A.grabAnims or A.swingAnims or {}) do
        local banned = c.clip and isForbidden(c.clip)

        if banned then
            print(('^1[BeyondSurvival]^7 (zombies) refusing grab candidate "%s / %s" - the clip name contains "%s", and walkers do not strike. Fix Zombies.Attack.grabAnims.')
                :format(tostring(c.dict), tostring(c.clip), tostring(banned)))

        elseif c.dict and DoesAnimDictExist(c.dict) then
            if not HasAnimDictLoaded(c.dict) then RequestAnimDict(c.dict) end
            local waited = 0
            while not HasAnimDictLoaded(c.dict) and waited < 2000 do
                Wait(10); waited = waited + 10
            end

            if HasAnimDictLoaded(c.dict) and clipIsReal(c.dict, c.clip) then
                Chosen = c
                print(('^2[BeyondSurvival]^7 (zombies) grab animation: %s / %s (played on the walker only - the player is never tasked)')
                    :format(c.dict, c.clip))
                return true
            end

            print(('^3[BeyondSurvival]^7 (zombies) "%s" has no clip "%s" on this build - trying the next one')
                :format(c.dict, tostring(c.clip)))
        end
    end

    print('^1[BeyondSurvival]^7 (zombies) no grab animation resolved - walkers will still claw, it will just not be visible')
    return false
end

-- Resolved at start, not at the first swing. ensureAnim yields
CreateThread(function()
    Wait(8000)
    ensureAnim()
end)

-- The clip in use, or nil. Never read A.swingAnims directly.
local function anim() return Chosen end

-- The swing is played on the walker only, never on a player
local function playSwing(ped)
    if not ped or not DoesEntityExist(ped) or not ensureAnim() then return end
    local a = anim()

    -- Walker only
    if NetworkGetEntityIsNetworked(ped) and not NetworkHasControlOfEntity(ped) then return end
    pcall(TaskPlayAnim, ped, a.dict, a.clip, 8.0, -8.0, A.swingTime or 1100,
        a.flag or 48, 0.0, false, false, false)
end

local function stopSwing(ped)
    if not ped or not DoesEntityExist(ped) then return end
    if NetworkGetEntityIsNetworked(ped) and not NetworkHasControlOfEntity(ped) then return end
    local a = anim()
    if a then pcall(StopAnimTask, ped, a.dict, a.clip, 2.0) end
end

-- Arms-out silhouette layered over the shamble
function Zombies.SetReaching(entry, on)
    if not R.enabled or not entry.reacher then return end
    if entry.reaching == on then return end

    local ped = entry.ped
    if not DoesEntityExist(ped) then return end

    if on then
        if not DoesAnimDictExist(R.dict) then
            print(('^3[BeyondSurvival]^7 (zombies) reach anim "%s" is not on this build'):format(R.dict))
            R.enabled = false
            return
        end

        if not HasAnimDictLoaded(R.dict) then RequestAnimDict(R.dict) end
        local waited = 0
        while not HasAnimDictLoaded(R.dict) and waited < 2000 do Wait(10); waited = waited + 10 end
        if not HasAnimDictLoaded(R.dict) then return end

        -- Flag 49 = upper body + looped
        if not pedOk(ped) or not HasAnimDictLoaded(R.dict) then return end
        TaskPlayAnim(ped, R.dict, R.clip, 4.0, -4.0, -1, R.flag or 49, 0.0, false, false, false)
    else
        -- No anim calls on a ped we do not own.
        if NetworkGetEntityIsNetworked(ped) and not NetworkHasControlOfEntity(ped) then
            entry.reaching = on
            return
        end
        StopAnimTask(ped, R.dict, R.clip, 2.0)
    end

    entry.reaching = on
end

-- Reaching is driven by the synced state so every client agrees on which walkers have their arms out
CreateThread(function()
    while true do
        Wait(500)
        if R.enabled and Zed then
            for _, entry in pairs(Zed.live) do
                if entry.reacher and DoesEntityExist(entry.ped) and not entry.dying then
                    Zombies.SetReaching(entry, entry.state == 'hunting')
                end
            end
        end
    end
end)

-- The swing

-- One swing
-- @return boolean  true if a swing actually started
local function evaded(me, startedDodging)
    if startedDodging then return true, 'dodge' end
    if GetResourceState('bs_skills') == 'started' then
        local ok, d = pcall(function() return exports.bs_skills:IsDodging() end)
        if ok and d then return true, 'dodge' end
    end
    local v = GetEntityVelocity(me)
    local speed = math.sqrt(v.x * v.x + v.y * v.y)
    if speed < (A.evadeSpeed or 1.8) then return false, 'slow' end

    -- Moving: are you running into something?
    local p = GetEntityCoords(me)
    local probe = A.cornerProbe or 1.2
    local tx, ty = p.x + (v.x / speed) * probe, p.y + (v.y / speed) * probe
    local h = StartExpensiveSynchronousShapeTestLosProbe(p.x, p.y, p.z, tx, ty, p.z, 1 | 2 | 16, me, 7)
    local _, hit = GetShapeTestResult(h)
    if hit == 1 or hit == true then return false, 'cornered' end

    local crowd = 0
    for _, e in pairs(Zed.live or {}) do
        if e.ped and DoesEntityExist(e.ped) and not e.dying and #(GetEntityCoords(e.ped) - p) <= 2.5 then
            crowd = crowd + 1
        end
    end
    if crowd >= (A.cornerCrowd or 3) then return false, 'surrounded' end
    return true, 'moving'
end

function Zombies.TryStrike(entry)
    if Swing.active then return false end
    if not entry or not entry.ped or not DoesEntityExist(entry.ped) then return false end
    if entry.dying or IsEntityDead(entry.ped) then return false end

    local now = GetGameTimer()
    if entry.nextAttack and now < entry.nextAttack then return false end

    local player = PlayerPedId()
    if IsPedDeadOrDying(player, true) then return false end

    -- Zombie godmode, not plain godmode
    if isZombieGodmoded() then return false end

    -- Walkers on the ground do not attack
    if IsPedRagdoll(entry.ped) then return false end

    -- Already on the floor bleeding out? Being chewed on adds nothing.
    if GetResourceState('bs_medical') == 'started' then
        local ok, downed = pcall(function() return exports.bs_medical:IsDowned() end)
        if ok and downed then return false end
    end

    if #(GetEntityCoords(entry.ped) - GetEntityCoords(player)) > (A.range or 1.55) then
        return false
    end

    Crumb('grab', 'start id=%s', tostring(entry.id))
    -- Each grab gets its own token and deadline
    entry.nextAttack = now + (A.cooldown or 1400)
    Swing.token    = Swing.token + 1
    Swing.active   = true
    Swing.id       = entry.id
    Swing.stage    = 'windup'
    Swing.deadline = now + (A.windup or 420) + (A.swingTime or 1100)
                         + (A.strandedGraceMs or 2500)

    local token = Swing.token

    Zombies.Growl(entry, 'attack')

    -- Turn to face the player. Only the walker turns.
    local zAt = GetEntityCoords(entry.ped)
    local pAt = GetEntityCoords(player)
    if not NetworkGetEntityIsNetworked(entry.ped) or NetworkHasControlOfEntity(entry.ped) then
        SetEntityHeading(entry.ped, GetHeadingFromVector_2d(pAt.x - zAt.x, pAt.y - zAt.y))
    end

    playSwing(entry.ped)

    -- Everyone else sees the same walker swing at the same moment.
    entry.state = 'grab'
    TriggerServerEvent('bs:z:grab', entry.id, true)

    -- Every exit from the resolve thread releases the grab
    local function release(stage)
        if Swing.token ~= token then return end
        Swing.active = false
        Swing.id     = nil
        Swing.stage  = stage or 'done'
    end

    CreateThread(function()
        -- Body runs under pcall and the release happens afterwards no matter what
        local ok, err = pcall(function()

        -- The windup makes the attack avoidable
        local dodgedAtStart = false
        if GetResourceState('bs_skills') == 'started' then
            local okD, d = pcall(function() return exports.bs_skills:IsDodging() end)
            dodgedAtStart = okD and d == true
        end
        Wait(A.windup or 420)
        Swing.stage = 'claw'

        local me = PlayerPedId()
        local connected =
            DoesEntityExist(entry.ped)
            and not IsEntityDead(entry.ped)
            and not IsPedDeadOrDying(me, true)
            and #(GetEntityCoords(entry.ped) - GetEntityCoords(me)) <= (A.reach or 1.9)
        if connected then
            local miss, why = evaded(me, dodgedAtStart)
            if miss then
                connected = false
                Crumb('grab', 'missed id=%s (%s)', tostring(entry.id), why)
            end
        end

        if connected then
            -- Damage is local (the engine owns health); infection is the server's call and is the lasting part
            local sealed = Zombies.PlayerProtectedInVehicle and Zombies.PlayerProtectedInVehicle()
            if not isGodmode() and not sealed then
                -- Worn armour reduces the bite
                local bite = (A.biteDamage or 12) * ZDiff.Local('damage')
                local stopped = 0.0

                if GetResourceState('bs_inventory') == 'started' then
                    local ok, stats = pcall(function()
                        return exports.bs_inventory:EquipmentStats()
                    end)
                    if ok and type(stats) == 'table' then
                        stopped = math.max(0.0, tonumber(stats.armour) or 0.0)
                    end
                end

                local taken = math.max(A.minBite or 2, bite - stopped)

                -- Energy shield booster soaks the bite first (bs_boosters).
                if GetResourceState('bs_boosters') == 'started' then
                    local okS, left = pcall(function()
                        return exports.bs_boosters:AbsorbZombieDamage(taken)
                    end)
                    if okS and type(left) == 'number' then taken = left end
                end

                local health = GetEntityHealth(me)
                SetEntityHealth(me, math.max(0, health - math.floor(taken + 0.5)))
                -- Shield soaked the whole bite: no skin contact, no infection.
                if taken > 0 then
                    TriggerServerEvent('bs:zombies:bitten', entry.typeId)
                end

                -- Garments that absorbed damage wear out
                if stopped > 0 then
                    TriggerServerEvent('bs:inventory:wearWorn', stopped)
                end
            end

            ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', sealed and 0.06 or 0.18)
            if not sealed then CreateThread(function()
                SetTimecycleModifier('rply_motionblur')
                Wait(400)
                ClearTimecycleModifier()
            end) end
        end

        -- Let the grab finish, then put the walker back to hunting.
        Swing.stage = 'settle'
        Wait(math.max(0, (A.swingTime or 1100) - (A.windup or 420)))

        -- DoesEntityExist is checked inside stopSwing on the frame the native is called
        stopSwing(entry.ped)
        entry.state = 'hunting'
        TriggerServerEvent('bs:z:grab', entry.id, false)

        end)

        if not ok then
            print(('^1[BeyondSurvival]^7 (zombies) a grab threw at stage "%s": %s - releasing it so walkers keep attacking.')
                :format(tostring(Swing.stage), tostring(err)))
        end

        release('done')
    end)

    return true
end

-- Old name kept because other code and older saves call it. Same as a walker attacking you.
Zombies.TryGrab = Zombies.TryStrike

-- Another player is attacked: play the same swing on our copy of the walker so everyone sees the lunge
RegisterNetEvent('bs:z:grabbed', function(id, victimSrc, holding)
    local entry = Zed and Zed.live[id]
    if not entry or not DoesEntityExist(entry.ped) then return end
    if victimSrc == GetPlayerServerId(PlayerId()) then return end   -- ours already runs
    Crumb('grab', 'remote id=%s victim=%s', tostring(id), tostring(victimSrc))

    entry.state = holding and 'grab' or 'hunting'

    if holding then
        playSwing(entry.ped)
    else
        stopSwing(entry.ped)
    end
end)

-- Every client checks walkers near itself, hosted or not
CreateThread(function()
    while true do
        Wait(150)

        if not Swing.active and Zed and exports.bs_core:IsLoaded() then
            local player = PlayerPedId()

            if not IsPedDeadOrDying(player, true) then
                local at = GetEntityCoords(player)

                for _, entry in pairs(Zed.live) do
                    if not entry.dying and DoesEntityExist(entry.ped)
                       and not IsEntityDead(entry.ped)
                       and #(GetEntityCoords(entry.ped) - at) <= (A.range or 1.55) then

                        if Zombies.TryStrike(entry) then break end
                    end
                end
            end
        end
    end
end)

-- A swing that never finished must not block the next one
local function clearSwing()
    -- The token changes too, so any thread still holding the old one will not clear a later grab.
    Swing.token    = Swing.token + 1
    Swing.active   = false
    Swing.id       = nil
    Swing.deadline = 0
    Swing.stage    = 'idle'
end

AddEventHandler('bs:hook:player:unloaded', clearSwing)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then clearSwing() end
end)

-- Watchdog times each grab, not the client
CreateThread(function()
    while true do
        Wait(1000)

        if Swing.active and Swing.deadline > 0 and GetGameTimer() > Swing.deadline then
            print(('^3[BeyondSurvival]^7 (zombies) grab on walker %s stranded at stage "%s" (%dms past its deadline) - releasing it.')
                :format(tostring(Swing.id), tostring(Swing.stage),
                        GetGameTimer() - Swing.deadline))
            clearSwing()
        end
    end
end)

-- Nothing holds the player, so this always answers false. bs_core's unstick check calls it.
exports('IsGrabbed', function() return false end)
exports('IsBeingAttacked', function() return Swing.active end)
