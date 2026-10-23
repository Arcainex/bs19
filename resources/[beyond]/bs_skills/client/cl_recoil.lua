-- Per-shot recoil + camera shake. Tunables: config/config_recoil.lua, notes: docs/RECOIL.md.
-- Only runs per-frame while a firearm is in hand; idles at 300ms otherwise.

local cfg
local UNARMED = GetHashKey('WEAPON_UNARMED')

local GROUPS = {
    [GetHashKey('GROUP_PISTOL')]  = 'pistol',
    [GetHashKey('GROUP_SMG')]     = 'smg',
    [GetHashKey('GROUP_RIFLE')]   = 'rifle',
    [GetHashKey('GROUP_MG')]      = 'mg',
    [GetHashKey('GROUP_SHOTGUN')] = 'shotgun',
    [GetHashKey('GROUP_SNIPER')]  = 'sniper',
    [GetHashKey('GROUP_HEAVY')]   = 'heavy',
}

local profileCache = {}          -- weapon hash -> merged profile (false = not a gun)
local suppHashes, gripHashes = {}, {}

local burst       = 0.0          -- climb applied this burst (deg)
local lastShotAt  = 0
local recovering  = false
local recStart, recTotal, recDone = 0, 0.0, 0.0
local ourShakeUntil = 0

local function profileFor(hash)
    local p = profileCache[hash]
    if p ~= nil then return p end
    local group = GROUPS[GetWeapontypeGroup(hash)]
    if not group then profileCache[hash] = false; return false end
    p = {}
    for k, v in pairs(cfg.groups[group] or {}) do p[k] = v end
    for name, o in pairs(cfg.weapons or {}) do
        if GetHashKey(name) == hash then for k, v in pairs(o) do p[k] = v end end
    end
    profileCache[hash] = p
    return p
end

local function hasAny(ped, weapon, list)
    for _, c in ipairs(list) do
        if HasPedGotWeaponComponent(ped, weapon, c) then return true end
    end
    return false
end

local function skillMult()
    local level, max = 0, 20
    pcall(function() level = exports.bs_skills:GetSkillLevel(cfg.tree) or 0 end)
    local tree = Skills.Trees and Skills.Trees[cfg.tree]
    if tree and tree.maxLevel then max = tree.maxLevel end
    local t = math.max(0.0, math.min(1.0, level / math.max(1, max)))
    local m = cfg.lowSkillMult + (cfg.highSkillMult - cfg.lowSkillMult) * t
    local ok, perk = pcall(function() return exports.bs_skills:HasPerk(cfg.tree, 'steady_hands') end)
    if ok and perk == true then m = m * (cfg.steadyHandsMult or 1.0) end
    -- bs_drugs interface: same sway modifier cl_sway uses
    local dm = LocalPlayer.state.bsDrugMods
    if type(dm) == 'table' and tonumber(dm.sway) then
        m = m * math.max(cfg.drugMin, math.min(cfg.drugMax, dm.sway))
    end
    -- Focus booster (bs_boosters)
    local st = tonumber(LocalPlayer.state.bsSteady)
    if st then m = m * math.max(0.3, math.min(1.0, st)) end
    return m
end

local function onShot(ped, weapon, p, now)
    if recovering then recovering = false; burst = burst - recDone end
    if now - lastShotAt > 600 then burst = 0.0 end
    lastShotAt = now

    local m = skillMult() * (BSConfigGet and tonumber(BSConfigGet('Global.recoilMultiplier', 1.0)) or 1.0)
    local climbCut, shakeCut = 0.0, 0.0
    if hasAny(ped, weapon, suppHashes) then climbCut = climbCut + cfg.suppressor.climb; shakeCut = shakeCut + cfg.suppressor.shake end
    if hasAny(ped, weapon, gripHashes) then climbCut = climbCut + cfg.grip.climb; shakeCut = shakeCut + cfg.grip.shake end
    local fp = GetFollowPedCamViewMode() == 4 and (cfg.firstPersonMult or 1.0) or 1.0

    local kick = p.kick * m * fp * (1.0 - math.min(0.9, climbCut)) * (0.85 + math.random() * 0.3)
    kick = math.max(0.0, math.min(kick, p.maxClimb - burst))
    local drift = (math.random() * 2.0 - 1.0) * p.drift * m

    pcall(function()
        if kick > 0.0 then
            SetGameplayCamRelativePitch(GetGameplayCamRelativePitch() + kick, 1.0)
            burst = burst + kick
        end
        SetGameplayCamRelativeHeading(GetGameplayCamRelativeHeading() + drift)
    end)

    -- Don't stomp a shake someone else started (bs_drugs withdrawal).
    if IsGameplayCamShaking() and now > ourShakeUntil then return end
    local amp = math.min(cfg.shakeMax, p.shake * (1.0 - math.min(0.9, shakeCut)) * math.min(m, 1.2))
    if amp > 0.0 then
        local name = p.shake >= cfg.bigShakeFrom and cfg.bigShakeName or cfg.shakeName
        ShakeGameplayCam(name, amp)
        ourShakeUntil = now + 400
    end
    if cfg.debug then
        print(('[recoil] kick %.2f drift %.2f burst %.2f shake %.2f'):format(kick, drift, burst, amp))
    end
end

local function stepRecovery(now)
    if not recovering then
        if burst > 0.0 and now - lastShotAt >= cfg.recoverDelayMs then
            recovering, recStart, recTotal, recDone = true, now, burst * cfg.recoverFraction, 0.0
        end
        return
    end
    local t = math.min(1.0, (now - recStart) / math.max(1, cfg.recoverMs))
    local target = recTotal * (1.0 - (1.0 - t) * (1.0 - t))   -- ease out
    local d = target - recDone
    if d > 0.0 then
        pcall(function() SetGameplayCamRelativePitch(GetGameplayCamRelativePitch() - d, 1.0) end)
        recDone = target
    end
    if t >= 1.0 then recovering, burst = false, 0.0 end
end

CreateThread(function()
    cfg = Skills and Skills.Recoil
    if not cfg or not cfg.enabled then
        print('^3[BeyondSurvival]^7 (skills) cl_recoil.lua: Skills.Recoil missing or disabled.')
        return
    end
    for _, n in ipairs(cfg.suppressorComponents or {}) do suppHashes[#suppHashes + 1] = GetHashKey(n) end
    for _, n in ipairs(cfg.gripComponents or {}) do gripHashes[#gripHashes + 1] = GetHashKey(n) end

    while true do
        local ped = PlayerPedId()
        local weapon = GetSelectedPedWeapon(ped)
        local p = weapon ~= UNARMED and weapon ~= 0 and profileFor(weapon)

        if not p or IsPedInAnyVehicle(ped, false) then
            burst, recovering = 0.0, false
            Wait(300)
        else
            local now = GetGameTimer()
            if IsPedShooting(ped) and now - lastShotAt >= cfg.shotGapMs then
                onShot(ped, weapon, p, now)
            elseif burst > 0.0 then
                stepRecovery(now)
            end
            Wait(0)
        end
    end
end)
