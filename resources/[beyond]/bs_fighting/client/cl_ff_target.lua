-- bs_fighting v3 - shared client state, checks and the target picker.
-- Targets: walkers (bs_zombies) and players in range, picked by camera-relative movement input.

FF = {
    target = nil,        -- { ped, kind = 'zombie'|'player', id, dist }
    busy = false,        -- a swing, counter, dodge or finisher is running
    combo = 0, lastHitAt = 0, lastActionAt = 0,
    windup = nil,        -- { id, ped, hitAt } latest walker swing at us
    lock = nil,          -- locked target (right mouse), same shape as target
    level = 0,
}

local S = Freeflow.Settings
local UNARMED = `WEAPON_UNARMED`
local GROUP_MELEE, GROUP_UNARMED = `GROUP_MELEE`, `GROUP_UNARMED`

function FF.Level()
    local ok, v = pcall(function() return exports.bs_skills:GetSkillLevel('fighting') end)
    if ok and type(v) == 'number' then FF.level = v end
    return FF.level
end

function FF.HasPerk(id)
    if not id or id == '' then return false end
    local ok, v = pcall(function() return exports.bs_skills:HasPerk(id) end)
    return ok and v == true
end

function FF.Stamina()
    local ok, n = pcall(function() return exports.bs_core:GetNeeds() end)
    return (ok and type(n) == 'table' and tonumber(n.stamina)) or 100.0
end

function FF.Spend(cost) pcall(function() exports.bs_core:AdjustStamina(-cost) end) end

function FF.FirstPerson() return GetFollowPedCamViewMode() == 4 end

function FF.Zombies() return GetResourceState('bs_zombies') == 'started' end

-- 'unarmed' | 'small_wpn' | 'large_wpn' | 'knife' | nil (gun), plus the weapon hash
function FF.WeaponClass(ped)
    local w = GetSelectedPedWeapon(ped)
    if w == 0 or w == UNARMED then return 'unarmed', UNARMED end
    local known = Fighting.ClassOfHash and Fighting.ClassOfHash(w)
    if known then return Freeflow.ClassMap[known] or 'unarmed', w end
    local g = GetWeapontypeGroup(w)
    if g == GROUP_UNARMED then return 'unarmed', w end
    if g == GROUP_MELEE then return 'small_wpn', w end
    return nil, w
end

function FF.Clips(class) return Freeflow.Clips[class or 'unarmed'] or Freeflow.Clips.unarmed end

function FF.CanFight(ped)
    if not S.enabled or (Fighting.Settings and Fighting.Settings.enabled == false) then return false end
    if IsNuiFocused() or IsPauseMenuActive() then return false end
    if IsPedInAnyVehicle(ped, true) or not IsPedOnFoot(ped) then return false end
    if IsPedDeadOrDying(ped, true) or IsPedRagdoll(ped) or IsPedGettingUp(ped) then return false end
    if IsPedSwimming(ped) or IsPedFalling(ped) or IsPedClimbing(ped) or IsPedCuffed(ped) then return false end
    if IsEntityAttached(ped) then return false end
    local ls = LocalPlayer.state
    if ls.bsDowned or ls.bsDrone or ls.bsSitting or ls.bsTakedown then return false end
    if type(ls.bsParkour) == 'table' and ls.bsParkour.active then return false end
    if GetResourceState('bs_building') == 'started' then
        local ok, placing = pcall(function() return exports.bs_building:IsPlacing() end)
        if ok and placing then return false end
    end
    return FF.WeaponClass(ped) ~= nil
end

function FF.InCombat()
    local now = GetGameTimer()
    if now - FF.lastActionAt < S.combatMs then return true end
    return FF.windup ~= nil and now - (FF.windup.at or 0) < S.combatMs
end

-- What a ped is to us: 'zombie', id | 'player', serverId | nil
function FF.Classify(p)
    if IsPedAPlayer(p) then
        if not Freeflow.PvP.enabled then return nil end
        local idx = NetworkGetPlayerIndexFromPed(p)
        if idx and idx ~= -1 then return 'player', GetPlayerServerId(idx) end
        return nil
    end
    if FF.Zombies() then
        local ok, id = pcall(function() return exports.bs_zombies:WalkerIdOf(p) end)
        if ok and id then return 'zombie', id end
    end
    return nil
end

function FF.IsDown(t)
    local p = t.ped
    if IsPedRagdoll(p) or IsPedGettingUp(p) then return true end
    if t.kind == 'zombie' and FF.Zombies() then
        local ok, c = pcall(function() return exports.bs_zombies:IsCrawlerPed(p) end)
        if ok and c then return true end
    end
    return false
end

function FF.IsStaggered(t)
    if t.kind ~= 'zombie' or not FF.Zombies() then return false end
    local ok, v = pcall(function() return exports.bs_zombies:IsStaggered(t.id) end)
    return ok and v == true
end

local function camForward()
    local rz = math.rad(GetGameplayCamRot(2).z)
    return -math.sin(rz), math.cos(rz)
end

-- Movement input turned into a world direction, or nil when the stick/keys are idle
local function inputDir()
    local x = GetDisabledControlNormal(0, 30)     -- left/right
    local y = -GetDisabledControlNormal(0, 31)    -- forward is negative
    local m = math.sqrt(x * x + y * y)
    if m < 0.2 then return nil end
    x, y = x / m, y / m
    local fx, fy = camForward()
    -- right of the camera is (fy, -fx)
    return fx * y + fy * x, fy * y - fx * x
end

local function valid(t, at, range)
    if not t or not DoesEntityExist(t.ped) or IsEntityDead(t.ped) then return false end
    local to = GetEntityCoords(t.ped)
    return #(to - at) <= range and math.abs(to.z - at.z) < S.maxHeightGap
end

-- Pick the target for the next action. Locked by the caller for the length of a swing.
function FF.Pick()
    local me = PlayerPedId()
    local at = GetEntityCoords(me)
    -- a locked target takes every attack, counter and finisher
    if FF.lock and valid(FF.lock, at, S.lockBreakRange) then
        FF.lock.dist = #(GetEntityCoords(FF.lock.ped) - at)
        FF.target = FF.lock
        return FF.lock
    end
    local dx, dy = inputDir()
    local list = {}
    for _, p in ipairs(GetGamePool('CPed')) do
        if p ~= me and not IsEntityDead(p) then
            local to = GetEntityCoords(p)
            local d = #(to - at)
            if d <= S.pickRange and math.abs(to.z - at.z) < S.maxHeightGap then
                local kind, id = FF.Classify(p)
                if kind then list[#list + 1] = { ped = p, kind = kind, id = id, dist = d, to = to } end
            end
        end
    end
    local best
    if dx then
        for _, t in ipairs(list) do
            local vx, vy = t.to.x - at.x, t.to.y - at.y
            local len = math.max(0.01, math.sqrt(vx * vx + vy * vy))
            if (vx * dx + vy * dy) / len > S.pickDot and (not best or t.dist < best.dist) then best = t end
        end
    end
    if not best then
        if valid(FF.target, at, S.pickRange) then
            local t = FF.target
            t.dist = #(GetEntityCoords(t.ped) - at)
            return t
        end
        local fx, fy = camForward()
        for _, t in ipairs(list) do
            local vx, vy = t.to.x - at.x, t.to.y - at.y
            local len = math.max(0.01, math.sqrt(vx * vx + vy * vy))
            if t.dist <= S.idleRange and (vx * fx + vy * fy) / len > S.idleDot and (not best or t.dist < best.dist) then best = t end
        end
    end
    FF.target = best
    return best
end

-- Small marker over the current target while in combat
CreateThread(function()
    while true do
        local t = FF.lock or FF.target
        if S.marker and t and DoesEntityExist(t.ped) and not IsEntityDead(t.ped) and (FF.lock or FF.InCombat()) then
            local c = S.markerColor
            local h = GetEntityCoords(t.ped)
            if #(h - GetEntityCoords(PlayerPedId())) > S.pickRange + 1.0 then
                FF.target = nil
            else
                if FF.lock then
                    -- locked: bigger chevron plus a ring at its feet
                    local lc = S.lockColor or c
                    DrawMarker(0, h.x, h.y, h.z + 1.15, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.18, 0.18, 0.14,
                        lc[1], lc[2], lc[3], lc[4], true, true, 2, false, nil, nil, false)
                    DrawMarker(25, h.x, h.y, h.z - 0.97, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.9, 0.9, 0.9,
                        lc[1], lc[2], lc[3], math.floor(lc[4] * 0.6), false, false, 2, false, nil, nil, false)
                else
                    DrawMarker(0, h.x, h.y, h.z + 1.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.12, 0.12, 0.10,
                        c[1], c[2], c[3], c[4], false, true, 2, false, nil, nil, false)
                end
            end
            Wait(0)
        else
            if t and (not DoesEntityExist(t.ped) or IsEntityDead(t.ped)) then FF.target = nil end
            Wait(150)
        end
    end
end)

-- Lock-on (right mouse). Breaks on death, distance or lost sight.

function FF.Unlock()
    if not FF.lock then return end
    FF.lock = nil
    if FFHud and FFHud.Locked then FFHud.Locked(false) end
end

function FF.Lock()
    local me = PlayerPedId()
    if not FF.CanFight(me) then return false end
    FF.lock = nil
    local t = FF.Pick()
    if not t then return false end
    FF.lock = t
    FF.lastActionAt = GetGameTimer()
    if FFHud and FFHud.Locked then FFHud.Locked(true) end
    return true
end

CreateThread(function()
    local lostSince, nextLos = 0, 0
    while true do
        local t = FF.lock
        if not t then
            lostSince = 0
            Wait(150)
        else
            local me = PlayerPedId()
            local now = GetGameTimer()
            local ok = DoesEntityExist(t.ped) and not IsEntityDead(t.ped) and FF.CanFight(me) or (FF.busy and DoesEntityExist(t.ped) and not IsEntityDead(t.ped))
            local a, b = GetEntityCoords(me), ok and GetEntityCoords(t.ped) or nil
            if ok and #(b - a) > S.lockBreakRange then ok = false end
            if ok and now >= nextLos then
                nextLos = now + 100
                if HasEntityClearLosToEntity(me, t.ped, 17) then lostSince = 0
                elseif lostSince == 0 then lostSince = now end
            end
            if ok and lostSince > 0 and now - lostSince > S.lockLosMs then ok = false end
            if not ok then
                FF.Unlock()
            else
                FF.lastActionAt = math.max(FF.lastActionAt, now - S.combatMs + 1000)
                local bearing = GetHeadingFromVector_2d(b.x - a.x, b.y - a.y)
                local dt = GetFrameTime()
                -- face the target when standing or stepping straight at it; sideways input is left to
                -- the walk, which circles it because the camera stays on it. A move owns the heading.
                local ix, iy = GetDisabledControlNormal(0, 30), -GetDisabledControlNormal(0, 31)
                local idle = ix * ix + iy * iy < 0.04 or (math.abs(ix) < 0.3 and iy > 0.5)
                if not FF.busy and idle and not IsPedRagdoll(me) then
                    SetEntityHeading(me, FFA.TurnTo(GetEntityHeading(me), bearing, math.min(1.0, dt * S.lockTurnRate)))
                end
                -- the camera keeps it centred, so sideways input circles it
                if S.lockCamera then
                    local rel = ((bearing - GetEntityHeading(me) + 540.0) % 360.0) - 180.0
                    local cur = GetGameplayCamRelativeHeading()
                    local d = ((rel - cur + 540.0) % 360.0) - 180.0
                    SetGameplayCamRelativeHeading(cur + d * math.min(1.0, dt * S.lockCamRate))
                end
                Wait(0)
            end
        end
    end
end)
