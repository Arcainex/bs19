-- Input, perks, carry weight, falls and zombie chases.

local S, T = Parkour.Settings, Parkour.Tuning

local PERKS = {
    'pk_basics', 'pk_advanced', 'pk_high_reach', 'pk_long_slide', 'pk_wall_runner', 'pk_double_wall', 'pk_cat_balance',
    'pk_spring_heels', 'pk_steady_breath', 'pk_iron_grip', 'pk_soft_landing', 'pk_pack_mule', 'pk_second_wind',
    'pk_marathon', 'pk_cat_landing', 'pk_quick_recovery', 'pk_breakaway', 'pk_adrenaline', 'pk_shake_off',
    'pk_low_profile', 'pk_ghost_runner', 'pk_escape_artist',
}

local function refreshPerks()
    if GetResourceState('bs_skills') ~= 'started' then return end
    local out = {}
    for _, id in ipairs(PERKS) do
        local ok, v = pcall(function() return exports.bs_skills:HasPerk(id) end)
        out[id] = ok and v == true or nil
    end
    PK.perks = out
    local ok, lvl = pcall(function() return exports.bs_skills:GetSkillLevel('parkour') end)
    PK.level = ok and tonumber(lvl) or 0
end
AddEventHandler('bs:skills:changed', refreshPerks)
CreateThread(function() while true do refreshPerks() Wait(10000) end end)

-- Weight comes down with the inventory state
RegisterNetEvent('bs:inventory:state', function(payload)
    if type(payload) ~= 'table' or type(payload.player) ~= 'table' then return end
    local w, m = tonumber(payload.player.weight) or 0, tonumber(payload.player.maxWeight) or 40
    PK.weight = m > 0 and w / m or 0.0
end)

function PK.Limits()
    return {
        vault = T.vaultMax,
        climb = T.climbMax,
        climbHigh = T.climbHighMax + (PK.Has('pk_high_reach') and 0.6 or 0.0),
        hang = T.hangMax + (PK.Has('pk_high_reach') and 0.4 or 0.0),
    }
end

local function blocked(ped)
    if IsPedInAnyVehicle(ped, true) or IsPedSwimming(ped) or IsPedRagdoll(ped) or IsEntityDead(ped) then return true end
    if IsPedCuffed(ped) or IsPlayerFreeAiming(PlayerId()) or IsPedInCover(ped, false) then return true end
    if GetResourceState('bs_medical') == 'started' then
        local ok, down = pcall(function() return exports.bs_medical:IsDowned() end)
        if ok and down then return true end
    end
    if GetResourceState('bs_inventory') == 'started' then
        local ok, open = pcall(function() return exports.bs_inventory:IsOpen() end)
        if ok and open then return true end
    end
    return false
end

-- What Space would do right now, or nil to leave the jump alone.
local function contextMove(ped)
    if PK.busy or blocked(ped) or IsPedFalling(ped) or IsPedJumping(ped) then return nil end
    local info = Detect.Front(ped, 1.3, PK.Limits())
    if not info then return nil end
    local kind = info.kind
    if kind == 'vault' or kind == 'climb' then
        -- Engine climbs work without training too; trained ones count
        if PK.Allowed(kind) and PK.Ready(kind) then return kind, info end
        return nil
    end
    if kind == 'climbHigh' and PK.Allowed('climbHigh') and PK.Ready('climbHigh') then return kind, info end
    if kind == 'ledge' and PK.Allowed('ledge') and PK.Ready('ledge') then return kind, info end
    return nil
end

local function run(kind, info)
    if kind == 'vault' or kind == 'climb' then PK.Start(kind, PK.Native, kind, info)
    elseif kind == 'climbHigh' then PK.Start(kind, PK.ClimbHigh, info)
    elseif kind == 'ledge' then PK.Start(kind, PK.Hang, info) end
end

-- Space near an obstacle
CreateThread(function()
    local pending, info, nextProbe = nil, nil, 0
    while true do
        local sleep = 250
        if S.enabled and S.contextJump and (PK.Has('pk_basics')) then
            sleep = 0
            local ped = PlayerPedId()
            local now = GetGameTimer()
            if now >= nextProbe then
                nextProbe = now + (S.probeMs or 90)
                pending, info = contextMove(ped)
            end
            if pending then
                DisableControlAction(0, 22, true)
                if IsDisabledControlJustPressed(0, 22) then
                    run(pending, info)
                    pending = nil
                    nextProbe = now + 400
                end
            end
        end
        Wait(sleep)
    end
end)

-- Dedicated key: wall run beside a wall, run up a wall ahead, otherwise a sprint slide
local function moveKey()
    if not S.enabled then return end
    local ped = PlayerPedId()
    PK.keyAt = GetGameTimer()
    if PK.busy then return end
    if IsPedFalling(ped) or IsPedJumping(ped) then
        PK.rollPressedAt = GetGameTimer()
        -- rising from a jump next to a wall: wall run (once per jump, twice with Double wall). Never while falling.
        local maxRuns = PK.Has('pk_double_wall') and 2 or 1
        if IsPedJumping(ped) and not IsPedFalling(ped) and PK.airRuns < maxRuns and PK.Allowed('wallrun') and PK.Ready('wallrun') then
            local side, n = Detect.Side(ped, 1.3)
            if side then PK.Start('wallrun', PK.WallRun, side, n) end
        end
        return
    end
    if blocked(ped) then return end
    local sprinting = IsPedSprinting(ped) or IsPedRunning(ped)
    if not sprinting then return end
    if PK.Allowed('wallrun') and PK.Ready('wallrun') then
        local side, n = Detect.Side(ped, 1.3)
        if side then PK.Start('wallrun', PK.WallRun, side, n) return end
        local info = Detect.Front(ped, 1.8, PK.Limits())
        if info and (info.kind == 'wall' or info.kind == 'ledge') and PK.Allowed('walljump') and PK.Ready('walljump') then PK.Start('walljump', PK.WallUp, info) return end
    end
    if PK.Allowed('slide') and PK.Ready('slide') and IsPedSprinting(ped) then
        PK.Start('slide', PK.Slide)
    end
end
-- New command name so the Mouse 4 default reaches players who already had the old C binding saved
RegisterCommand('+bsparkourmove', moveKey, false)
RegisterCommand('-bsparkourmove', function() end, false)
RegisterKeyMapping('+bsparkourmove', 'Parkour: wall run / slide / run up a wall', S.moveKeyDevice or 'MOUSE_BUTTON', S.moveKey or 'MOUSE_EXTRABTN1')

-- Admin dev check (server command parkouranims): which clips load, optionally play one in place
RegisterNetEvent('bs:parkour:animcheck', function(kind)
    local rows = PK.AnimReport()
    print('^3[bs_parkour] animation check^7')
    for _, r in ipairs(rows) do
        print(('%-9s %-40s %-32s %s'):format(r.kind, r.dict, r.clip,
            not r.exists and '^1no dict^7' or not r.loaded and '^1not loaded^7' or r.length <= 0 and '^1no clip^7' or ('^2ok %.2fs^7'):format(r.length)))
    end
    if type(kind) == 'string' and Parkour.Anims[kind] then
        local ped = PlayerPedId()
        local a = PK.AnimFor(kind)
        if a then
            PK.debugUntil = GetGameTimer() + 5000
            TaskPlayAnim(ped, a.dict, a.clip, 6.0, 3.0, 5000, 0, 0.0, false, false, false)
            print(('playing %s: %s / %s'):format(kind, a.dict, a.clip))
        else
            print(('no working clip for %s'):format(kind))
        end
    end
    TriggerEvent('bs:ui:notify', { type = 'info', message = 'Parkour animation check printed to F8.', duration = 3000 })
end)

-- No shooting mid-move, a short shake after
CreateThread(function()
    local shaking = false
    while true do
        local now = GetGameTimer()
        if PK.busy and S.noFireDuringMove then
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 257, true)
            Wait(0)
        elseif now < PK.penaltyUntil then
            if not shaking and IsPlayerFreeAiming(PlayerId()) then
                ShakeGameplayCam('HAND_SHAKE', S.aimPenaltyShake or 0.35)
                shaking = true
            end
            Wait(0)
        else
            if shaking then StopGameplayCamShaking(true) shaking = false end
            Wait(150)
        end
    end
end)

-- Falls: passive damage reduction from the skill, and a roll when timed (or always with Cat landing)
function PK.FallReduction()
    local r = math.min(S.fallReduceMax or 0.5, (PK.level or 0) * (S.fallReducePerLevel or 0))
    if PK.Has('pk_soft_landing') then r = r + 0.15 end
    return math.min(0.9, r)
end

CreateThread(function()
    local falling, topZ, guarded = false, 0.0, false
    while true do
        local ped = PlayerPedId()
        local sleep = 100
        if S.enabled and not IsPedInAnyVehicle(ped, false) then
            local z = GetEntityCoords(ped).z
            local inAir = IsPedFalling(ped) or (IsPedJumping(ped) and GetEntityVelocity(ped).z < -2.0)
            if inAir and not PK.busy then
                sleep = 0
                if not falling then falling, topZ = true, z end
                topZ = math.max(topZ, z)
                local drop = topZ - z
                local vz = GetEntityVelocity(ped).z
                if IsDisabledControlJustPressed(0, 22) or IsControlJustPressed(0, 22) then PK.rollPressedAt = GetGameTimer() end
                local wants = PK.FallReduction() > 0 or PK.Has('pk_basics')
                -- Take over the landing just before impact, then apply our own damage
                if wants and not guarded and drop > S.fallSafeHeight * 0.6 and vz < -5.0 and GetEntityHeightAboveGround(ped) < 2.2
                   and not GetPlayerInvincible(PlayerId()) then
                    SetEntityInvincible(ped, true)
                    guarded, PK.fallGuard = true, true
                end
            elseif falling then
                falling = false
                PK.airRuns = 0
                local drop = topZ - z
                if guarded then
                    Wait(60)
                    SetEntityInvincible(ped, false)
                    guarded, PK.fallGuard = false, nil
                    if not IsEntityInWater(ped) then
                        local maxRoll = PK.Has('pk_cat_landing') and 12.0 or S.rollMaxHeight
                        local timed = PK.rollPressedAt and GetGameTimer() - PK.rollPressedAt <= (S.rollWindowMs or 450) + 200
                        local roll = PK.Allowed('roll') and drop >= S.rollMinHeight and drop <= maxRoll
                                     and (timed or PK.Has('pk_cat_landing'))
                        local dmg = math.max(0.0, drop - S.fallSafeHeight) * S.fallHpPerMetre * (1.0 - PK.FallReduction())
                        if roll then
                            dmg = dmg * 0.25
                            PK.Start('roll', PK.Roll)
                        end
                        if dmg >= 1.0 then ApplyDamageToPed(ped, math.floor(dmg), false) end
                    end
                end
                PK.rollPressedAt = nil
            end
        else
            if guarded then SetEntityInvincible(ped, false) guarded, PK.fallGuard = false, nil end
            falling = false
        end
        Wait(sleep)
    end
end)

-- Second wind: a landed big move gives a little stamina back
AddEventHandler('bs:parkour:moved', function(kind)
    if PK.Has('pk_second_wind') and (Parkour.Moves[kind] or {}).stamina and Parkour.Moves[kind].stamina > 0 then
        pcall(function() exports.bs_core:AdjustStamina(5) end)
    end
end)

-- Chases: a walker close for a few seconds is a chase; losing every walker breaks it
CreateThread(function()
    local nearSince, lostSince, chaseFrom = nil, nil, nil
    while true do
        Wait(1000)
        if S.enabled and S.escapeEnabled and PK.Has('pk_basics') and GetResourceState('bs_zombies') == 'started' then
            local ped = PlayerPedId()
            local me = GetEntityCoords(ped)
            local close, any = false, false
            local lost = S.lostRange * (PK.Has('pk_escape_artist') and 0.75 or 1.0)
            for _, z in ipairs(GetGamePool('CPed')) do
                if z ~= ped and not IsPedAPlayer(z) and not IsEntityDead(z) then
                    local d = #(GetEntityCoords(z) - me)
                    if d <= lost then
                        local ok, walker = pcall(function() return exports.bs_zombies:IsWalkerPed(z) end)
                        if ok and walker then
                            any = true
                            if d <= S.chaseRange then close = true break end
                        end
                    end
                end
            end
            local now = GetGameTimer()
            if IsEntityDead(ped) then
                nearSince, lostSince, PK.chasing = nil, nil, false
            elseif not PK.chasing then
                if close then
                    nearSince = nearSince or now
                    if now - nearSince >= S.chaseMinSeconds * 1000 then
                        PK.chasing, chaseFrom, lostSince = true, me, nil
                        TriggerServerEvent('bs:parkour:chase')
                    end
                else nearSince = nil end
            else
                if any then lostSince = nil
                else
                    lostSince = lostSince or now
                    local need = S.lostSeconds * 1000 * (PK.Has('pk_escape_artist') and 0.7 or 1.0)
                    if now - lostSince >= need then
                        PK.chasing, nearSince = false, nil
                        if chaseFrom and #(me - chaseFrom) >= S.escapeMinDistance then
                            TriggerServerEvent('bs:parkour:escape')
                        end
                    end
                end
            end
        else
            PK.chasing = false
        end
    end
end)

-- Reads for other resources (zombies can skip grabs while this is true)
exports('IsInMove', function() return PK.busy end)
exports('CurrentMove', function() return PK.move end)
exports('IsChased', function() return PK.chasing end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    PK.Cleanup(PK.busy)
end)

-- Watchdog: a move past its time limit, or a parkour clip still playing with no move running, is cancelled
CreateThread(function()
    local strayed = 0
    while true do
        Wait(250)
        local ped = PlayerPedId()
        local now = GetGameTimer()
        if PK.busy then
            strayed = 0
            local max = (PK.MaxMs or {})[PK.move or ''] or 4000
            if PK.startedAt and now - PK.startedAt > max then
                print(('^3[bs_parkour] %s ran %d ms, cancelled^7'):format(tostring(PK.move), now - PK.startedAt))
                PK.Cleanup(true)
            end
        elseif now > (PK.debugUntil or 0) then
            local stray = false
            for _, a in ipairs(PK.KnownClips()) do
                if IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then stray = true StopAnimTask(ped, a.dict, a.clip, 3.0) end
            end
            local st = LocalPlayer.state.bsParkour
            if PK.frozen or (type(st) == 'table' and st.active) then stray = true end
            strayed = stray and strayed + 1 or 0
            -- give a normal blend out a moment before forcing it
            if strayed >= 3 then
                print('^3[bs_parkour] leftover parkour state cleared^7')
                PK.Cleanup(true)
                strayed = 0
            end
        end
    end
end)

-- Emergency: /parkourreset puts the ped back to normal at once
RegisterCommand('parkourreset', function()
    local ped = PlayerPedId()
    PK.Cleanup(true)
    if PK.fallGuard then SetEntityInvincible(ped, false) PK.fallGuard = nil end
    ClearPedTasksImmediately(ped)
    PK.airRuns, PK.rollPressedAt, PK.keyAt = 0, nil, nil
    TriggerEvent('bs:ui:notify', { type = 'info', message = L('pk.reset'), duration = 2500 })
end, false)

-- Start clean (bs_emotes skips its double-tap stumble while a move is active)
LocalPlayer.state:set('bsParkour', { active = false }, true)

-- Debug menu (bs_fpdebug)
exports('DebugData', function()
    local rows, kinds, bad = PK.AnimReport(), {}, {}
    for k in pairs(Parkour.Anims) do kinds[#kinds + 1] = k end
    table.sort(kinds)
    for _, r in ipairs(rows) do
        if not r.exists or not r.loaded or r.length <= 0 then bad[#bad + 1] = r.kind .. ' ' .. r.dict .. '/' .. r.clip end
    end
    return { kinds = kinds, failed = bad }
end)

exports('DebugPlay', function(kind)
    local ped = PlayerPedId()
    local a = PK.AnimFor(kind)
    if not a then return false end
    ClearPedTasks(ped)
    PK.debugUntil = GetGameTimer() + 3000
    TaskPlayAnim(ped, a.dict, a.clip, 6.0, 3.0, 2500, 0, 0.0, false, false, false)
    return true
end)
