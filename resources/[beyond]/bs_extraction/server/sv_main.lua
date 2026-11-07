-- bs_extraction - server side. Client reports are claims, not facts: zone membership (speed checked), player kills (checked against server-tracked zones) and extraction (re-measured against the player's position at call time).

local state         = {}   -- [src] = { inZone, lastPos, lastUpdate, rogueUntil, bounty }
local pairKills     = {}   -- ['lowSrc:highSrc'] = os.time of last accepted kill either way
local killCooldown  = {}   -- ['attacker>victim'] = os.time of last paid kill

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function notify(src, kind, message)
    TriggerClientEvent('bs:ui:notify', src, { type = kind, message = message, duration = 3800 })
end

local function setRogue(src, value)
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then Player(src).state:set('bsRogue', value or false, true) end
end

local function setInRaid(src, zoneId)
    Player(src).state:set('bsInRaid', zoneId or false, true)
end

--------------------------------------------------------------------------------
-- Loading / unloading
--------------------------------------------------------------------------------

AddEventHandler('bs:hook:player:loaded', function(player)
    if type(player) ~= 'table' or not player.source then return end
    local src = tonumber(player.source)
    if not src then return end

    state[src] = { inZone = nil, lastPos = nil, lastUpdate = 0, rogueUntil = nil, bounty = 0 }
end)

local function clear(src)
    state[src] = nil
end

AddEventHandler('bs:hook:player:unloaded', function(player)
    if type(player) ~= 'table' or not player.source then return end
    clear(tonumber(player.source))
end)

AddEventHandler('playerDropped', function()
    clear(source)
end)

-- Zone membership: self-reported, speed-checked.

RegisterNetEvent('bs:extraction:zoneUpdate', function(zoneId, x, y, z)
    local src = source
    local s = state[src]
    if not s then return end
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return end

    local now = os.time()
    if s.lastPos and s.lastUpdate > 0 then
        local dt = math.max(0.5, now - s.lastUpdate)
        local dx, dy, dz = x - s.lastPos.x, y - s.lastPos.y, z - s.lastPos.z
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        if (dist / dt) > (Extraction.Settings.maxPlausibleSpeed or 100.0) then
            -- Implausible jump: ignore the claim, keep the last good state.
            return
        end
    end

    s.lastPos = { x = x, y = y, z = z }
    s.lastUpdate = now

    if zoneId ~= nil and not Extraction.GetZone(zoneId) then zoneId = nil end
    if s.inZone ~= zoneId then
        s.inZone = zoneId
        setInRaid(src, zoneId)
    end
end)

-- Player kills inside a zone (rogue flagging and bounty payout). Reported by the victim's client, naming the attacker. Zones come from server-tracked `state[].inZone`, never from the client.

RegisterNetEvent('bs:extraction:playerKilled', function(attackerSrc)
    local victimSrc = source
    attackerSrc = tonumber(attackerSrc)
    if not attackerSrc or attackerSrc == victimSrc then return end
    if not GetPlayerName(attackerSrc) then return end

    -- The reported victim's ped must really be dead, otherwise two players could trade fake death claims for bounties. IsEntityDead is client-only, so this uses GetEntityHealth: the dead floor is 100, not 0. The dead flag is used first when a guarded call finds it.
    local victimPed = GetPlayerPed(victimSrc)
    if not victimPed or victimPed == 0 then return end

    local dead = false

    local okFlag, flag = pcall(IsEntityDead, victimPed)
    if okFlag and flag == true then
        dead = true
    else
        local okHealth, health = pcall(GetEntityHealth, victimPed)
        -- 100 is the engine's floor for a dead ped, not zero.
        if okHealth and type(health) == 'number' and health <= 100 then dead = true end
    end

    if not dead then return end

    local victim, attacker = state[victimSrc], state[attackerSrc]
    if not victim or not attacker then return end
    if not victim.inZone or victim.inZone ~= attacker.inZone then return end

    -- The victim names the killer, so check the killer is alive and close enough, to stop colluders passing bounties back and forth off one real death.
    local attackerPed = GetPlayerPed(attackerSrc)
    if not attackerPed or attackerPed == 0 then return end
    if GetEntityHealth(attackerPed) <= 100 then return end
    if #(GetEntityCoords(attackerPed) - GetEntityCoords(victimPed)) > 150.0 then return end

    -- The engine's record of the killer, when replicated. Zero proves nothing, so only a different non-zero killer rejects the claim.
    local okSrc, killerEnt = pcall(GetPedSourceOfDeath, victimPed)
    if okSrc and type(killerEnt) == 'number' and killerEnt ~= 0 and killerEnt ~= attackerPed then
        local okVeh, killerVeh = pcall(GetVehiclePedIsIn, attackerPed, false)
        if not (okVeh and killerVeh == killerEnt) then return end
    end

    local key = ('%d>%d'):format(attackerSrc, victimSrc)
    local now = os.time()

    -- Anti-farm: the same two players trading kills within ten minutes earn nothing.
    local pairKey = ('%d:%d'):format(math.min(attackerSrc, victimSrc), math.max(attackerSrc, victimSrc))
    local lastPair = pairKills[pairKey]
    pairKills[pairKey] = now
    if lastPair and (now - lastPair) < 600 then return end

    local cooldown = Extraction.Settings.killCooldownSeconds or 20
    if killCooldown[key] and (now - killCooldown[key]) < cooldown then return end
    killCooldown[key] = now

    -- Bounty collection: the victim was already Rogue. Pay the attacker and clear the flag before applying any new one.
    if victim.rogueUntil and now < victim.rogueUntil then
        local payout = math.max(Extraction.Settings.bountyBase, victim.bounty or 0)
        victim.rogueUntil = nil
        victim.bounty = 0
        setRogue(victimSrc, false)

        exports.bs_core:AddMoney(attackerSrc, 'cash', payout, 'bounty_collected')
        notify(attackerSrc, 'success', Lp(attackerSrc, 'ex.bounty_got', { n = payout }))
        notify(victimSrc, 'info', Lp(victimSrc, 'ex.collected'))

        -- A bounty kill is not fresh aggression, so do not flag the attacker Rogue too.
        return
    end

    -- Otherwise an ordinary zone kill: flag the attacker Rogue and stack their bounty.
    attacker.rogueUntil = now + (Extraction.Settings.rogueWindowSeconds or 300)
    attacker.bounty = (attacker.bounty or 0) > 0
        and (attacker.bounty + (Extraction.Settings.bountyPerKill or 250))
        or (Extraction.Settings.bountyBase or 500)
    setRogue(attackerSrc, true)

    notify(attackerSrc, 'warn', Lp(attackerSrc, 'ex.rogue', { n = attacker.bounty }))
    local zoneLabel = Extraction.GetZone(victim.inZone).label
    for _, id in ipairs(GetPlayers()) do
        TriggerClientEvent('bs:ui:notify', tonumber(id), {
            type = 'info', duration = 3200,
            message = Lp(tonumber(id), 'ex.went_rogue', { zone = zoneLabel }),
        })
    end
end)

-- Rogue flags expire on their own.
CreateThread(function()
    while true do
        Wait(15000)
        local now = os.time()
        for src, s in pairs(state) do
            if s.rogueUntil and now >= s.rogueUntil then
                s.rogueUntil = nil
                s.bounty = 0
                setRogue(src, false)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Extraction
--------------------------------------------------------------------------------

BSB.RegisterCallback('extraction:complete', function(src, zoneId, pointId)
    local s = state[src]
    if not s then return { ok = false, error = 'not loaded' } end

    local zone = Extraction.GetZone(zoneId)
    if not zone then return { ok = false, error = 'no such zone' } end

    local point = nil
    for _, p in ipairs(zone.extractionPoints) do
        if p.id == pointId then point = p; break end
    end
    if not point then return { ok = false, error = 'no such extraction point' } end

    -- Re-measured now from the server's position of the ped, not from the client's dwell time.
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { ok = false, error = 'no ped' } end

    local at = GetEntityCoords(ped)
    local dx, dy, dz = at.x - point.coords.x, at.y - point.coords.y, at.z - point.coords.z
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist > (point.radius or 6.0) then
        return { ok = false, error = Lp(src, 'ex.not_close') }
    end

    exports.bs_core:AddMoney(src, 'cash', zone.rewardMoney or 0, 'extraction')
    exports.bs_core:AddXP(src, zone.rewardXp or 0, 'extraction')

    s.inZone = nil
    setInRaid(src, nil)
    -- faction missions count this (bs_factions/sv_progression.lua)
    TriggerEvent('bs:extraction:completed', src, zone.id)

    return { ok = true, money = zone.rewardMoney or 0, xp = zone.rewardXp or 0, label = point.label }
end)

--------------------------------------------------------------------------------
-- Plain-data reads
--------------------------------------------------------------------------------

exports('IsInZone', function(src)
    local s = state[tonumber(src)]
    return s and s.inZone or nil
end)

exports('IsRogue', function(src)
    local s = state[tonumber(src)]
    return s ~= nil and s.rogueUntil ~= nil and os.time() < s.rogueUntil
end)

exports('GetBounty', function(src)
    local s = state[tonumber(src)]
    return s and s.bounty or 0
end)

--------------------------------------------------------------------------------
-- Staff
--------------------------------------------------------------------------------

RegisterCommand('zonestatus', function(src)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.admin') then return end
    local lines = {}
    for id, s in pairs(state) do
        if s.inZone then
            lines[#lines + 1] = ('%d: %s%s'):format(id, s.inZone,
                (s.rogueUntil and os.time() < s.rogueUntil) and (' ROGUE $' .. tostring(s.bounty)) or '')
        end
    end
    if src == 0 then
        print(#lines > 0 and table.concat(lines, '\n') or 'nobody in a zone')
    else
        notify(src, 'info', #lines > 0 and table.concat(lines, '  |  ') or Lp(src, 'ex.nobody_zone'))
    end
end, false)

exports.bs_core:RegisterModule('extraction', { side = 'server', version = '1.0.0', ready = true })
