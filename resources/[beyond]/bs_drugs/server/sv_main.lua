-- Server authority: item checks, consumption, timers, addiction.

local active = {}   -- src -> { [drug] = expiresAt (os.time) }
local lastUse = {}  -- src -> GetGameTimer()
local info = {}     -- src -> { [drug] = { q, dur } } for the HUD

local function notify(src, msg, kind)
    TriggerClientEvent('bs:ui:notify', src, { type = kind or 'info', message = msg, duration = 3500 })
end

local function count(src, item)
    local ok, n = pcall(function() return exports.bs_inventory:CountItem(src, item) end)
    return ok and tonumber(n) or 0
end

local function take(src, item)
    local ok, res = pcall(function() return exports.bs_inventory:RemoveItem(src, item, 1) end)
    return ok and res and true or false
end

local function alive(src)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and GetEntityHealth(ped) > 0
end

local function getAddiction(src)
    local ok, raw = pcall(function() return exports.bs_core:GetPlayerMeta(src, Drugs.MetaKey, nil) end)
    if not ok then return nil end
    local out = {}
    if type(raw) == 'table' then
        for drug, v in pairs(raw) do
            if Drugs.Types[drug] and type(v) == 'table' then
                out[drug] = { pts = tonumber(v.pts) or 0, last = tonumber(v.last) or 0 }
            end
        end
    end
    return out
end

local function setAddiction(src, a)
    pcall(function() exports.bs_core:SetPlayerMeta(src, Drugs.MetaKey, a) end)
end

local function levelOf(pts)
    local lvl = 0
    for i, t in ipairs(Drugs.Addiction.levels) do if pts >= t then lvl = i end end
    return lvl
end

-- Worst withdrawal across drugs that are not currently active.
local function withdrawal(src, a)
    local now, worst = os.time(), 0
    local act = active[src] or {}
    for drug, v in pairs(a or {}) do
        local on = act[drug] and act[drug] > now
        if not on and now - v.last >= Drugs.Addiction.withdrawalAfter then
            worst = math.max(worst, levelOf(v.pts))
        end
    end
    return worst
end

local function pushState(src)
    local a = getAddiction(src)
    if not a then return end
    local now, rem = os.time(), {}
    for drug, t in pairs(active[src] or {}) do
        if t > now then
            local i = info[src] and info[src][drug] or {}
            rem[drug] = { rem = t - now, dur = i.dur or (t - now), q = i.q or 'normal' }
        end
    end
    local pts = {}
    for drug, v in pairs(a) do pts[drug] = math.floor(v.pts) end
    TriggerClientEvent('bs:drugs:state', src, { withdrawal = withdrawal(src, a), addiction = pts, active = rem })
end

exports('BleedoutBonus', function(src)
    src = tonumber(src)
    local t = active[src] and active[src].morphine
    if t and t > os.time() then return Drugs.Types.morphine.bleedoutBonus end
    return 0
end)
exports('GetAddiction', function(src) return getAddiction(tonumber(src)) end)

local function useRehab(src)
    if not take(src, Drugs.RehabItem) then return end
    setAddiction(src, {})
    notify(src, Lp(src, 'drug.clean'), 'success')
    TriggerClientEvent('bs:drugs:anim', src, 'inject')
    pushState(src)
end

-- Fired by bs_inventory's use callback (server-side only, not a net event).
AddEventHandler('bs:drugs:use', function(src, item)
    src = tonumber(src)
    if not src or not alive(src) then return end
    local now = GetGameTimer()
    if lastUse[src] and now - lastUse[src] < Drugs.UseLockMs then return end
    lastUse[src] = now

    if item == Drugs.RehabItem then return useRehab(src) end

    local map = Drugs.Items[item]
    if not map then return end
    local t, q = Drugs.Types[map.drug], Drugs.Quality[map.q]
    if not t or not q then return end
    if count(src, item) < 1 then return end

    active[src] = active[src] or {}
    if map.drug == 'cigarette' and (active[src].cigarette or 0) > os.time() then
        notify(src, Lp(src, 'drug.smoking'), 'error'); return
    end

    -- Cigarette needs fire: lighter kept, matches used up.
    local fireUsed
    if t.needsFire then
        for _, f in ipairs(t.needsFire) do
            if count(src, f) > 0 then fireUsed = f; break end
        end
        if not fireUsed then notify(src, Lp(src, 'drug.lighter'), 'error'); return end
    end

    if not take(src, item) then return end
    if fireUsed and t.consumeFire and t.consumeFire[fireUsed] then take(src, fireUsed) end

    local duration = math.floor(t.duration * q.effect)
    active[src][map.drug] = os.time() + duration
    info[src] = info[src] or {}
    info[src][map.drug] = { q = map.q, dur = duration }

    local a = getAddiction(src) or {}
    local cur = a[map.drug] or { pts = 0, last = 0 }
    cur.pts = math.min(Drugs.Addiction.max, cur.pts + t.addict * q.addict)
    cur.last = os.time()
    a[map.drug] = cur
    setAddiction(src, a)

    TriggerClientEvent('bs:drugs:apply', src, map.drug, map.q, duration)
    pushState(src)
end)

-- Cigarette cancelled early (sprint/aim/damage) - end it server-side too.
RegisterNetEvent('bs:drugs:stopSmoking', function()
    local src = source
    if active[src] and active[src].cigarette then
        active[src].cigarette = nil
        pushState(src)
    end
end)

RegisterNetEvent('bs:drugs:request', function() pushState(source) end)

-- Decay addiction while clean, expire timers, refresh withdrawal.
CreateThread(function()
    while true do
        Wait(Drugs.Addiction.tickSeconds * 1000)
        local now = os.time()
        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)
            local act = active[src]
            if act then
                for drug, t in pairs(act) do if t <= now then act[drug] = nil end end
            end
            local a = getAddiction(src)
            if a and next(a) then
                local changed = false
                for drug, v in pairs(a) do
                    if not (act and act[drug]) and now - v.last >= Drugs.Addiction.cleanAfter then
                        v.pts = v.pts - Drugs.Addiction.decayPerMinute * (Drugs.Addiction.tickSeconds / 60)
                        changed = true
                        if v.pts <= 0 then a[drug] = nil end
                    end
                end
                if changed then setAddiction(src, a) end
                pushState(src)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    active[src], lastUse[src], info[src] = nil, nil, nil
end)
