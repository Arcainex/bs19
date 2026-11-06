-- Parkour v3 input, perks, carry weight, falls and zombie chases.
-- Space near an obstacle and the move key (Mouse 4 by default) both pick the obstacle move,
-- with coyote time and an input buffer. The move key alone, while sprinting, is the slide.

local S, T = Parkour.Settings, Parkour.Tuning
local P3 = Parkour.Pk3 or {}

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
    local high = PK.Advanced() and PK.Allowed('climbHigh')
    return {
        stepMin = P3.autoStep and (P3.stepMin or 0.3) or 0.45,
        stepMax = P3.autoStep and (P3.stepMax or 0.5) or 0.45,
        vault = T.vaultMax,
        vaultDepth = P3.vaultDepth or 1.0,
        maxDrop = P3.vaultMaxDrop or 2.5,
        climb = T.climbMax,
        climbHigh = high and (T.climbHighMax + (PK.Has('pk_high_reach') and 0.6 or 0.0)) or T.climbMax,
        bonnetMin = P3.bonnetMin or 0.6,
        bonnetMax = P3.bonnetMax or 1.25,
        bonnetDepth = P3.bonnetDepth or 3.2,
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

-- Detect kind -> the move it uses for permission, cooldown and XP
local MOVE_OF = { vault = 'vault', climb = 'climb', climbHigh = 'climbHigh', bonnet = 'bonnet', native = 'climb', step = 'step' }

local function usable(kind)
    local m = MOVE_OF[kind]
    return m ~= nil and PK.Allowed(m) and PK.Ready(m)
end

local function run(kind, info)
    if P3.useNative and kind ~= 'step' then kind = 'native' end
    -- vault and climb use GTA's own climb (real clips with IK) unless own clips are switched on
    if (kind == 'vault' or kind == 'climb') and not P3.ownVaultClimb then kind = 'native' end
    if kind == 'vault' then return PK.Start('vault', PK3.Vault, info)
    elseif kind == 'climb' then return PK.Start('climb', PK3.Climb, info, 'climb')
    elseif kind == 'climbHigh' then return PK.Start('climbHigh', PK3.Climb, info, 'climbHigh')
    elseif kind == 'bonnet' then return PK.Start('bonnet', PK3.Bonnet, info)
    elseif kind == 'step' then return PK.Start('step', PK3.Step, info)
    elseif kind == 'native' then return PK.Start('climb', PK3.NativeMove, 'climb', info) end
    return false
end

-- Last obstacle seen (Cand) and last tall wall seen (Wall), with the time they were seen
local Cand, Wall, PressAt, GroundAt, JumpAt = nil, nil, nil, 0, nil

-- Still in front of the face (not already past it) and close enough
local function ahead(ped, info)
    local p = GetEntityCoords(ped)
    local s = Detect.Dot2(p - info.wall, info.normal)
    return s > 0.05 and s < (P3.reachMax or 1.9) + 0.4
end

local function fresh(ped, c)
    return c and GetGameTimer() - c.at <= (P3.coyoteMs or 150) and ahead(ped, c.info)
end

local function fire(c)
    if not c then return false end
    Cand, PressAt = nil, nil
    return run(c.kind, c.info)
end

-- Probe: reads the obstacle ahead while on foot, plus a moment after leaving the ground
CreateThread(function()
    while true do
        local sleep = 250
        local ped = PlayerPedId()
        if S.enabled and IsPedOnFoot(ped) and not PK.busy and not blocked(ped) then
            sleep = P3.probeMs or 50
            local now = GetGameTimer()
            local air = IsPedFalling(ped) or IsPedJumping(ped) or IsPedInParachuteFreeFall(ped)
            if not air then GroundAt, JumpAt = now, nil
            elseif IsPedJumping(ped) and not JumpAt then JumpAt = now end
            local window = not air or now - GroundAt <= (P3.coyoteMs or 150) or (JumpAt and now - JumpAt <= (P3.jumpWindowMs or 300))
            if window then
                local speed = GetEntitySpeed(ped)
                local reach = math.max(1.0, math.min(P3.reachMax or 1.9, (P3.reachBase or 1.0) + speed * (P3.reachPerSpeed or 0.12)))
                local info = Detect.Front(ped, reach, PK.Limits())
                local t = GetGameTimer()
                if info and not PK.busy then
                    if info.kind == 'wall' then
                        Wall = { info = info, at = t }
                    elseif info.kind == 'step' then
                        if P3.autoStep and not air and speed > 1.0 and info.dist < 0.65 and usable('step') then run('step', info) end
                    elseif usable(info.kind) then
                        Cand = { kind = info.kind, info = info, at = t }
                    end
                end
                -- buffered press: Space a moment before the obstacle was read
                if PressAt and t - PressAt <= (P3.bufferMs or 120) + (P3.probeMs or 50) and fresh(ped, Cand) then fire(Cand) end
            end
        end
        Wait(sleep)
    end
end)

-- Space: takes over the jump only while a move is ready, otherwise the jump is left alone
CreateThread(function()
    while true do
        local sleep = 200
        if S.enabled and S.contextJump then
            local ped = PlayerPedId()
            if IsPedOnFoot(ped) and not PK.busy then
                sleep = 0
                if fresh(ped, Cand) then
                    DisableControlAction(0, 22, true)
                    if IsDisabledControlJustPressed(0, 22) then fire(Cand) end
                elseif IsControlJustPressed(0, 22) then
                    PressAt = GetGameTimer()
                    PK.rollPressedAt = PressAt
                end
            end
        end
        Wait(sleep)
    end
end)

-- Move key: obstacle move when one is ready, wall bounce on a tall wall (advanced), else the sprint slide
local function moveKey()
    if not S.enabled then return end
    local ped = PlayerPedId()
    PK.keyAt = GetGameTimer()
    if PK.busy then return end
    if IsPedFalling(ped) or IsPedJumping(ped) then
        PK.rollPressedAt = GetGameTimer()
        return
    end
    if blocked(ped) then return end
    if S.moveKeyObstacles ~= false and fresh(ped, Cand) and Cand.kind ~= 'step' then fire(Cand) return end
    local sprinting = IsPedSprinting(ped) or IsPedRunning(ped)
    if not sprinting then return end
    if fresh(ped, Wall) and Wall.info.dist <= 1.6 and PK.Allowed('walljump') and PK.Ready('walljump') then
        local w = Wall
        Wall = nil
        PK.Start('walljump', PK.WallUp, w.info)
        return
    end
    if PK.Allowed('slide') and PK.Ready('slide') and IsPedSprinting(ped) then
        PK.Start('slide', PK.Slide)
    end
end
-- Same command name as v1, so players keep their Mouse 4 (or custom) binding
RegisterCommand('+bsparkourmove', moveKey, false)
RegisterCommand('-bsparkourmove', function() end, false)
RegisterKeyMapping('+bsparkourmove', 'Parkour: slide / vault / climb', S.moveKeyDevice or 'MOUSE_BUTTON', S.moveKey or 'MOUSE_EXTRABTN1')

-- Admin dev check (server command parkouranims): which clips load, optionally play one in place
RegisterNetEvent('bs:parkour:animcheck', function(kind)
    local rows = PK.AnimReport()
    print('^3[bs_parkour] animation check^7')
    for _, r in ipairs(rows) do
        print(('%-10s %-40s %-32s %s'):format(r.kind, r.dict, r.clip,
            not r.exists and '^1no dict^7' or not r.loaded and '^1not loaded^7' or r.length <= 0 and '^1no clip^7' or ('^2ok %.2fs^7'):format(r.length)))
    end
    if type(kind) == 'string' then PK.DebugPlay(kind) end
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
                -- Take over the landing just before impact, then apply our own damage
                if not guarded and drop > S.fallSafeHeight * 0.6 and vz < -5.0 and GetEntityHeightAboveGround(ped) < 2.2
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
    PK.Cleanup(PK.busy or PK.colOff)
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
            local max = math.max((PK.MaxMs or {})[PK.move or ''] or 4000, PK.expectMs or 0)
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
            if PK.frozen or PK.colOff or (type(st) == 'table' and st.active) then stray = true end
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

-- T-pose guard: during a move and for 2 s after, a ped in the bind pose that is not in GTA's own
-- climb is put back to normal and the clip it was on is logged (F8) and banned for the session.
CreateThread(function()
    local hits = 0
    while true do
        local ped = PlayerPedId()
        local now = GetGameTimer()
        local watch = PK.busy or (PK.endedAt and now - PK.endedAt < 2000) or now < (PK.debugUntil or 0)
        if watch and not PK.testing and IsPedOnFoot(ped) and not IsPedClimbing(ped) and not IsPedVaulting(ped) and not IsPedRagdoll(ped) then
            if PK3.IsTPose(ped) then hits = hits + 1 else hits = 0 end
            if hits >= 2 then
                hits = 0
                local clip = PK3.lastClip or 'none'
                print(('^1[bs_parkour] T-pose caught (move %s, last clip %s), ped reset^7'):format(tostring(PK.move or 'after move'), clip))
                if PK3.lastClip and now >= (PK.debugUntil or 0) then PK3.bad[PK3.lastClip] = true end
                if PK.busy or PK.colOff then PK.Cleanup(true) end
                SetEntityCollision(ped, true, true)
                ClearPedTasks(ped)
                PK.debugUntil = 0
            end
            Wait(50)
        else
            hits = 0
            Wait(250)
        end
    end
end)

-- Emergency: /parkourreset puts the ped back to normal at once
RegisterCommand('parkourreset', function()
    local ped = PlayerPedId()
    PK.Cleanup(true)
    if PK.fallGuard then SetEntityInvincible(ped, false) PK.fallGuard = nil end
    SetEntityCollision(ped, true, true)
    ClearPedTasksImmediately(ped)
    PK.airRuns, PK.rollPressedAt, PK.keyAt = 0, nil, nil
    Cand, Wall, PressAt = nil, nil, nil
    TriggerEvent('bs:ui:notify', { type = 'info', message = L('pk.reset'), duration = 2500 })
end, false)

-- Start clean (bs_emotes skips its double-tap stumble while a move is active)
LocalPlayer.state:set('bsParkour', { active = false }, true)

-- Debug menu (bs_fpdebug)
exports('DebugData', function()
    local rows, kinds, bad = PK.AnimReport(), {}, {}
    for k in pairs(Parkour.Anims) do kinds[#kinds + 1] = k end
    table.sort(kinds)
    for _, set in ipairs(PK3.DebugSets()) do kinds[#kinds + 1] = set.id end
    for _, r in ipairs(rows) do
        if not r.exists or not r.loaded or r.length <= 0 then bad[#bad + 1] = r.kind .. ' ' .. r.dict .. '/' .. r.clip end
    end
    return { kinds = kinds, failed = bad }
end)

local function debugClip(kind)
    for _, set in ipairs(PK3.DebugSets()) do
        if set.id == kind then return PK3.Resolve(set.cands) end
    end
    return PK.AnimFor(kind) or nil
end

function PK.DebugPlay(kind)
    if PK.busy then return false end
    local ped = PlayerPedId()
    local a = debugClip(kind)
    if not a then return false end
    ClearPedTasks(ped)
    PK.debugUntil = GetGameTimer() + 3500
    TaskPlayAnim(ped, a.dict, a.clip, 6.0, 3.0, 3000, 0, 0.0, false, false, false)
    print(('[bs_parkour] playing %s: %s / %s'):format(kind, a.dict, a.clip))
    return true
end
exports('DebugPlay', function(kind) return PK.DebugPlay(kind) end)
