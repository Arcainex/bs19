-- bs_zombies - who a networked walker chases, decided once on the server

ZNetTarget = {
    hurt  = {},   -- [recordId] = { [src] = GetGameTimer() of the last validated hit }
    nolos = {},   -- [recordId] = { [src] = until (GetGameTimer) }
    stats = { passes = 0, changes = 0, nolos = 0 },
}

if not (ZNet and ZNet.enabled) then return end

local sqrt = math.sqrt

local function T() return (Zombies.Net and Zombies.Net.target) or {} end
local function num(v, d) v = tonumber(v); return v or d end

-- Damage memory
if ZSimSense and ZSimSense.ReportDamage then
    local original = ZSimSense.ReportDamage
    ZSimSense.ReportDamage = function(src, id)
        local rid = tonumber(id)
        if rid and src then
            ZNetTarget.hurt[rid] = ZNetTarget.hurt[rid] or {}
            ZNetTarget.hurt[rid][src] = GetGameTimer()
        end
        return original(src, id)
    end
end

RegisterNetEvent('bs:z:nolos', function(id, who)
    local src = source
    local record = Registry.zombies[tonumber(id)]
    who = tonumber(who)
    if not record or not who or record.netOwner ~= src then return end
    ZNetTarget.nolos[record.id] = ZNetTarget.nolos[record.id] or {}
    ZNetTarget.nolos[record.id][who] = GetGameTimer() + num(T().nolosMs, 2000)
    ZNetTarget.stats.nolos = ZNetTarget.stats.nolos + 1
end)

-- The pick

local function angleOk(zx, zy, zh, px, py, half)
    -- GTA heading: 0 = north (+y), counter-clockwise. Forward = (-sin h, cos h).
    local r = math.rad(zh or 0.0)
    local fx, fy = -math.sin(r), math.cos(r)
    local dx, dy = px - zx, py - zy
    local len = sqrt(dx * dx + dy * dy)
    if len < 0.01 then return true end
    return ((dx / len) * fx + (dy / len) * fy) >= math.cos(math.rad(half))
end

local function playersNow()
    local out = {}
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 and DoesEntityExist(ped) and GetEntityHealth(ped) > 0 then
            local at = GetEntityCoords(ped)
            local info = ZSimSense and ZSimSense.players and ZSimSense.players[src] or {}
            if not info.muted then
                out[#out + 1] = {
                    src = src, x = at.x, y = at.y, z = at.z,
                    crouched = info.crouched, prone = info.prone, stealth = info.stealth,
                    mult = info.mult or 1.0,
                }
            end
        end
    end
    return out
end

local function pick(record, ent, plist, now)
    local DET = (Noise and Noise.Detection) or {}
    local SG = DET.sight or {}
    local def = Zombies.Types and Zombies.Types[record.typeId or 'walker'] or {}
    local typeScale = num(def.senseRadius, 28.0) / num(SG.referenceSenseRadius, 28.0)
    local feeding = record.state == 'feeding'
    local feedScale = feeding and num(Zombies.Feeding and Zombies.Feeding.senseScale, 0.2) or 1.0
    local half = num(DET.visionHalfAngle, 80.0)
    local dmgWindow = num(Sim and Sim.sense and Sim.sense.damageTargetSeconds, 45) * 1000
    local dmgRange = num(T().damageChaseRange, 150.0)

    local zx, zy, zz = record.x, record.y, record.z or 0.0
    local zh = record.h or 0.0
    local hurt = ZNetTarget.hurt[record.id]
    local blocked = ZNetTarget.nolos[record.id]

    local best, bestD, bestWhy
    local curD, curWhy
    for i = 1, #plist do
        local p = plist[i]
        local dx, dy, dz = p.x - zx, p.y - zy, (p.z or zz) - zz
        local d = sqrt(dx * dx + dy * dy + dz * dz * 0.25)
        local why

        local hitAt = hurt and hurt[p.src]
        if hitAt and (now - hitAt) <= dmgWindow and d <= dmgRange then
            why = 'damage'
        else
            local low = p.prone or p.crouched or p.stealth
            local contact = low and num(SG.crouchedContactRadius, 1.2) or num(DET.contactRadius, 3.5)
            if d <= contact then
                why = 'contact'
            else
                local stance = p.prone and num(SG.prone, 6.0)
                    or ((p.crouched or p.stealth) and num(SG.crouched, 10.0))
                    or num(SG.standing, 50.0)
                local reach = stance * typeScale * feedScale * (p.mult or 1.0)
                if d <= reach and angleOk(zx, zy, zh, p.x, p.y, half) then
                    local until_ = blocked and blocked[p.src]
                    if not (until_ and now < until_) then why = 'sight' end
                end
            end
        end

        if why then
            if p.src == record.tgtSrc then curD, curWhy = d, why end
            if not best or d < bestD then best, bestD, bestWhy = p.src, d, why end
        end
    end

    -- "Nearest always", with a two-metre deadband
    if curD and best ~= record.tgtSrc and bestD > curD - num(T().switchMargin, 2.0) then
        return record.tgtSrc, curWhy
    end
    return best, bestWhy
end

local function setBag(ent, key, value)
    pcall(function() Entity(ent).state:set(key, value, true) end)
end

CreateThread(function()
    while true do
        Wait(num(T().tickMs, 300))
        -- Clients only defer to zTarget while this says so
        local on = T().enabled ~= false
        if GlobalState.bsZTargetServer ~= on then GlobalState.bsZTargetServer = on end
        if on then
            local now = GetGameTimer()
            local plist = playersNow()
            ZNetTarget.stats.passes = ZNetTarget.stats.passes + 1
            for ent, id in pairs(ZNet.ents) do
                local record = Registry.zombies[id]
                if record and record.ent == ent and DoesEntityExist(ent) and not record.dead then
                    local src, why = nil, nil
                    if #plist > 0 then src, why = pick(record, ent, plist, now) end

                    -- A short grace before letting go
                    if not src and record.tgtSrc and now < (record.tgtKeepUntil or 0) then
                        src, why = record.tgtSrc, record.tgtWhy
                    elseif src then
                        record.tgtKeepUntil = now + num(T().graceMs, 1500)
                    end

                    if src ~= record.tgtSrc or why ~= record.tgtWhy then
                        record.tgtSrc, record.tgtWhy = src, why
                        setBag(ent, 'zTarget', src or false)
                        setBag(ent, 'zTgtWhy', why or false)
                        ZNetTarget.stats.changes = ZNetTarget.stats.changes + 1
                    end
                end
            end
        end
    end
end)

-- Forget memory for walkers that no longer exist, once a minute.
CreateThread(function()
    while true do
        Wait(60000)
        local now = GetGameTimer()
        for id, t in pairs(ZNetTarget.hurt) do
            if not Registry.zombies[id] then ZNetTarget.hurt[id] = nil
            else
                for src, at in pairs(t) do if now - at > 120000 then t[src] = nil end end
            end
        end
        for id in pairs(ZNetTarget.nolos) do
            if not Registry.zombies[id] then ZNetTarget.nolos[id] = nil end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for _, t in pairs(ZNetTarget.hurt) do t[src] = nil end
    for _, t in pairs(ZNetTarget.nolos) do t[src] = nil end
end)
