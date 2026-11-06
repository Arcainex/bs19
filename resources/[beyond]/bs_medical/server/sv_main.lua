-- bs_medical - server clock: the server decides how long a downed player has, tells others via a state bag

local S = Medical.Settings
local Down = {}        -- [src] = { endsAt = os.time seconds, stabilised = bool }
local lastHardDeath = {}   -- [src] = os.time() of the last accepted hardDeath payout

-- Helpers

local function isDown(src) return Down[src] ~= nil end
MedicalIsDown = isDown
local DeadAt = {}        -- [src] = os.time() the death screen started

-- Drag/carry links, both directions. Declared here so finish() can break a carry when the downed player gets up or dies.
local CarriedBy = {}   -- [victim] = { carrier = src, mode = 'drag'|'carry' }
local Carrying  = {}   -- [carrier] = victim
local function clearCarry(src)
    local victim = Carrying[src] and Carrying[src] or (CarriedBy[src] and src)
    if not victim then return end
    local link = CarriedBy[victim]
    CarriedBy[victim] = nil
    if link then
        Carrying[link.carrier] = nil
        if GetPlayerName(link.carrier) then TriggerClientEvent('bs:medical:carry:stop', link.carrier) end
    end
    if GetPlayerName(victim) then TriggerClientEvent('bs:medical:carry:stop', victim) end
end

local Dead = {}         -- [src] = true while on the death screen, not respawned

local function syncRevivable(src)
    Player(src).state:set('bsRevivable', (Down[src] ~= nil) or (Dead[src] == true), true)
end

local function setStateBag(src, value)
    -- Replicated so clients can check whether a player is down without asking the server (instant interaction prompt).
    Player(src).state:set('bsDowned', value, true)
    syncRevivable(src)
end

local function setDead(src, value)
    Dead[src] = value or nil
    DeadAt[src] = value and os.time() or nil
    Player(src).state:set('bsDead', value and true or false, true)
    syncRevivable(src)
end

local function distanceBetween(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if not pa or pa == 0 or not pb or pb == 0 then return math.huge end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb))
end

-- Where the player fell, for the 500-1000 m scatter the client works out.
local function deathOrigin(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

local function nearestRespawn(src)
    -- A bedroll beats a clinic: someone who built a camp wakes up in it.
    if GetResourceState('bs_building') == 'started' then
        local player = exports.bs_core:GetPlayer(src)
        if player then
            local ok, point = pcall(function()
                return exports.bs_building:GetRespawnPoint(player.charId)
            end)
            if ok and type(point) == 'table' and point.x then return point, true end
        end
    end

    local ped = GetPlayerPed(src)
    local best, bestDist = S.respawnPoints[1], math.huge
    if not ped or ped == 0 then return best end

    local at = GetEntityCoords(ped)
    for _, point in ipairs(S.respawnPoints) do
        local d = #(at - vector3(point.x, point.y, point.z))
        if d < bestDist then best, bestDist = point, d end
    end
    return best
end

-- What a death costs you, in items.

local deaths = {}   -- [src] = { seq = n, wiped = bool }

-- Bumps the death counter and returns the record. Every path that decides a player died calls this once.
local function beginDeath(src)
    local record = deaths[src]
    if record then
        record.seq   = record.seq + 1
        record.wiped = false
    else
        record = { seq = 1, wiped = false }
        deaths[src] = record
    end
    return record
end

-- Empties the dead player's inventory, once per death.
local function wipeForDeath(src)
    if not S.wipeOnDeath then return end

    local record = deaths[src]
    if not record or record.wiped then return end
    record.wiped = true

    if GetResourceState('bs_inventory') ~= 'started' then return end

    -- Dark Zone death (bs_darkzone): only the contaminated bag drops, the rest is kept.
    if GetResourceState('bs_darkzone') == 'started' then
        local okDz, kept = pcall(function() return exports.bs_darkzone:OnDeath(src) end)
        if okDz and kept == true then return end
    end

    -- Everything goes into the body first (sv_corpse.lua), then the hook.
    if Corpse and Corpse.FromDeath then
        local ok, err = pcall(Corpse.FromDeath, src)
        if not ok then print(('^1[BS MEDICAL]^7 body failed for %s: %s'):format(src, tostring(err))) end
    end

    -- Hook first, while there is still something to take. A corpse system depends on this order.
    TriggerEvent('bs:medical:death:beforeWipe', src)

    -- Uses the export: WipeInventory clears the grid, hotbar bindings, equipment slots and ped weapons.
    local ok, err = pcall(function() return exports.bs_inventory:WipeInventory(src) end)
    if not ok then
        print(('^1[BS MEDICAL]^7 death wipe failed for %s: %s'):format(src, tostring(err)))
    end
end

-- Going down, and the end of it

local function goDown(src)
    if isDown(src) then return Down[src] end

    -- Morphine (bs_drugs) buys extra seconds before bleeding out.
    local extra = 0
    if GetResourceState('bs_drugs') == 'started' then
        local ok, n = pcall(function() return exports.bs_drugs:BleedoutBonus(src) end)
        extra = ok and tonumber(n) or 0
    end
    Down[src] = { endsAt = os.time() + S.bleedoutTime + extra, stabilised = false }
    setStateBag(src, true)

    local player = exports.bs_core:GetPlayer(src)
    print(('^3[BS MEDICAL]^7 %s went down'):format(player and player.name or src))

    return Down[src]
end

local function finish(src, revived)
    if not isDown(src) then return end
    clearCarry(src)
    Down[src] = nil
    Player(src).state:set('bsFlatline', false, true)
    setStateBag(src, false)

    if revived then
        exports.bs_core:SetPlayerMeta(src,'survivorLink',nil)
        if GetResourceState('bs_guard') == 'started' then pcall(function() exports.bs_guard:Allow(src, 'teleport', 15000) end) end
        TriggerClientEvent('bs:medical:revived', src)
        return
    end

    -- Bled out. Needs are knocked back, but infection is not cleared.
    local point, bedroll = nearestRespawn(src)
    local from = (not bedroll) and deathOrigin(src) or nil

    -- Run the corpse hook and the wipe before telling the client anything, so the fade and teleport do not race the wipe.
    beginDeath(src)
    wipeForDeath(src)
    if MedicalOnDeath then MedicalOnDeath(src) end

    -- bs_guard: the respawn teleport is legit (detection layer, log only)
    if GetResourceState('bs_guard') == 'started' then pcall(function() exports.bs_guard:Allow(src, 'teleport', 30000) end) end
    TriggerClientEvent('bs:medical:died', src, point, from)

    local player = exports.bs_core:GetPlayer(src)
    if player then
        exports.bs_core:RestoreNeeds(src,
            S.respawnHunger - (player.needs.hunger or 0),
            S.respawnThirst - (player.needs.thirst or 0))
    end

    TriggerEvent('bs:db:insert', [[
        INSERT INTO `bs_character_stats` (`character_id`, `deaths`)
        VALUES (?, 1)
        ON DUPLICATE KEY UPDATE `deaths` = `deaths` + 1
    ]], { player and player.charId or 0 })
end

-- One timer for everyone who is down.
CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        local rate = (Medical.Carry and Medical.Carry.bleedoutRate) or 0.0
        for src, record in pairs(Down) do
            -- Being dragged or carried slows (or pauses) the bleed: push the end back by the part of this second that did not count.
            if CarriedBy[src] and rate < 1.0 then
                record.endsAt = record.endsAt + (1.0 - rate)
            end
            if not GetPlayerName(src) then
                Down[src] = nil
            elseif now >= record.endsAt then
                -- Medical system on: the heart stops first and a defibrillator can still bring them back for a short while.
                local window = MedicalOn and MedicalOn() and math.floor(Medical.System.defibWindow or 0) or 0
                if not record.flat and window > 0 then
                    record.flat = true
                    record.endsAt = now + window
                    clearCarry(src)
                    Player(src).state:set('bsFlatline', true, true)
                    TriggerClientEvent('bs:medical:flatline', src, window)
                else
                    finish(src, false)
                end
            end
        end
    end
end)

-- Hard death: the downed catch is skipped.

local HARD_DEATH_COOLDOWN = 5 -- seconds

-- A first press used to be thrown away: the client sees its own ped dead at once

local HARD_DEATH_GRACE_MS = 1500

-- Respawn check. Every failure path returns a distinct `error`, never a bare { ok = false }, and the handler body runs in its own pcall and reports throws.
-- The old confirmDead check is gone: IsEntityDead is a client native (it throws on the server), and GetEntityHealth <= 0 is unreliable because the death floor is 100 and downed players sit at 105.
-- Now: accept unless the server can positively see a healthy ped. Accept on a readable dead flag, health at or below the downed window, a player registered Down, or a view the server cannot resolve. Refuse only while the ped reads clearly above the window for the whole grace.
-- The cooldown below is the second half of the exploit guard (free teleports/needs).

-- Health at or below which a ped is dead or in the downed catch.
local DOWNED_FLOOR = (S.catchHealth or 106) + 1

-- Reads a native that may not exist on the server or may raise on a despawning ped.
local function tryNative(fn, ...)
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return value
end

-- Can the server positively see this player alive and well?
local function looksAliveAndWell(src, graceMs)
    local waited = 0
    while true do
        if not GetPlayerName(src) then return false end   -- gone; nothing to refuse

        local ped = tryNative(GetPlayerPed, src)
        if not ped or ped == 0 then return false end      -- no view: do not refuse

        -- Server-side IsEntityDead may not exist; tryNative turns that into nil (unknown, not alive).
        if tryNative(IsEntityDead, ped) == true then return false end

        local health = tryNative(GetEntityHealth, ped)
        if health == nil then return false end            -- unreadable: do not refuse
        if health <= DOWNED_FLOOR then return false end   -- dead, or in the catch band
        if isDown(src) then return false end              -- Already agree they are down

        if waited >= graceMs then return true end         -- healthy for the whole grace
        Wait(100)
        waited = waited + 100
    end
end

-- The whole hard-death payout in one place so the caller can pcall it and show a message instead of a silent 8s timeout.
local function runHardDeath(src)
    if not S.enabled then
        return { ok = false, error = Lp(src, 'med.the_medical_system_is_switched_off_o') }
    end

    local now = os.time()
    if now - (lastHardDeath[src] or 0) < HARD_DEATH_COOLDOWN then
        return { ok = false, error = Lp(src, 'med.too_soon') }
    end

    if looksAliveAndWell(src, HARD_DEATH_GRACE_MS) then
        return { ok = false, error = Lp(src, 'med.the_server_still_sees_you_on_your_fe') }
    end

    -- Medical system: the body stays a while so a defibrillator can reach it.
    local window = MedicalOn and MedicalOn() and math.floor(Medical.System.defibWindow or 0) or 0
    if window > 0 and DeadAt[src] and now - DeadAt[src] < window then
        return { ok = false, error = Lp(src, 'respawn_wait', { s = window - (now - DeadAt[src]) }), wait = window - (now - DeadAt[src]) }
    end

    clearCarry(src)
    -- Confirmed dead while registered Down: the catch did not hold.
    if isDown(src) then Down[src] = nil end
    -- Always, so nobody keeps being offered Lp(src, 'med.treat_wounds') after respawning.
    Dead[src] = nil
    DeadAt[src] = nil
    Player(src).state:set('bsDead', false, true)
    setStateBag(src, false)

    local player = exports.bs_core:GetPlayer(src)
    if not player then
        -- Character not loaded server-side, so there is nothing to pay out to. Say so.
        return { ok = false, error = Lp(src, 'med.your_character_is_not_loaded_on_the') }
    end

    exports.bs_core:SetPlayerMeta(src,'survivorLink',nil)
    lastHardDeath[src] = now

    local point, bedroll = nearestRespawn(src)
    local from = (not bedroll) and deathOrigin(src) or nil
    if not point then
        -- Not observed (S.respawnPoints is not empty), but a nil point would mean a respawn with no teleport.
        return { ok = false, error = Lp(src, 'med.no_respawn_point_is_configured_tell') }
    end

    -- Same order as finish(): corpse hook, wipe, payout.
    beginDeath(src)
    wipeForDeath(src)
    if MedicalOnDeath then MedicalOnDeath(src) end

    exports.bs_core:RestoreNeeds(src,
        S.respawnHunger - (player.needs.hunger or 0),
        S.respawnThirst - (player.needs.thirst or 0))

    TriggerEvent('bs:db:insert', [[
        INSERT INTO `bs_character_stats` (`character_id`, `deaths`)
        VALUES (?, 1)
        ON DUPLICATE KEY UPDATE `deaths` = `deaths` + 1
    ]], { player.charId or 0 })

    print(('^3[BS MEDICAL]^7 %s died outright (no catch window)'):format(player.name or src))

    return { ok = true, point = point, from = from }
end

BSB.RegisterCallback('medical:hardDeath', function(src)
    -- Self-reporting: this pcall logs the player and the error and tells the player a throw happened
    local ok, result = pcall(runHardDeath, src)
    if ok and type(result) == 'table' then return result end

    print(('^1[BS MEDICAL]^7 hardDeath threw for %s (%s): %s'):format(
        GetPlayerName(src) or '?', src, tostring(result)))

    return { ok = false, error = Lp(src, 'med.the_server_errored_handling_your_dea') }
end)

-- Callbacks

BSB.RegisterCallback('medical:down', function(src, reason)
    -- Failures here return an `error` string too (never a bare { ok = false }).
    if not S.enabled then
        return { ok = false, error = Lp(src, 'med.the_medical_system_is_switched_off_o') }
    end
    if not exports.bs_core:GetPlayer(src) then
        return { ok = false, error = Lp(src, 'med.your_character_is_not_loaded_on_the') }
    end

    -- The client says it is down; the ped has to agree.
    local ped = GetPlayerPed(src)
    local health = 0
    if ped and ped ~= 0 then health = GetEntityHealth(ped) end
    -- A PvP catch resurrects the ped in place at 105, and the server's copy can still show full health briefly.
    local limit = (S.catchHealth or 106) + 5
    if (reason == 'pvp' or reason == 'catch') then
        local waited = 0
        while health > limit and waited < 2000 do
            Wait(100) waited = waited + 100
            ped = GetPlayerPed(src)
            health = (ped and ped ~= 0) and GetEntityHealth(ped) or 0
        end
    end
    if not ped or ped == 0 or health > limit then
        return { ok = false, error = Lp(src, 'med.the_server_does_not_see_you_as_hurt') }
    end

    if Dead[src] then setDead(src, false) end
    local record = goDown(src)
    return { ok = true, seconds = math.max(1, record.endsAt - os.time()) }
end)

-- Bandaging yourself. Once per downing, and it costs the bandage.
BSB.RegisterCallback('medical:stabilise', function(src)
    local record = Down[src]
    if not record then return { ok = false, error = Lp(src, 'med.you_are_not_down_you_are_not_down') } end
    if record.flat then return { ok = false, error = Lp(src, 'med.no_pulse_no_pulse') } end
    if record.stabilised and not S.stabiliseUnlimited then return { ok = false, error = Lp(src, 'med.you_have_already_packed_it') } end

    if S.stabiliseItem then
        if exports.bs_inventory:CountItem(src, S.stabiliseItem) < 1 then
            return { ok = false, error = Lp(src, 'med.no_bandage') }
        end
        exports.bs_inventory:RemoveItem(src, S.stabiliseItem, 1)
    end

    record.stabilised = true
    record.endsAt = record.endsAt + S.stabiliseBonus

    return { ok = true, bonus = S.stabiliseBonus }
end)

-- Giving up uses the same death as any other: finish(src, false)
BSB.RegisterCallback('medical:giveUp', function(src)
    if not S.enabled then
        return { ok = false, error = Lp(src, 'med.the_medical_system_is_switched_off_o') }
    end
    if not isDown(src) then
        return { ok = false, error = Lp(src, 'med.you_are_not_bleeding_out') }
    end

    local player = exports.bs_core:GetPlayer(src)
    print(('^3[BS MEDICAL]^7 %s gave up and bled out'):format(player and player.name or src))

    -- The bleedout path. Sends bs:medical:died to the client, the same screen the timer running out gives.
    finish(src, false)

    return { ok = true }
end)

-- Someone else's bandage. Also once, and it does not pick them up.
BSB.RegisterCallback('medical:stabiliseOther', function(src, targetSrc)
    targetSrc = tonumber(targetSrc)
    local record = targetSrc and Down[targetSrc]
    if not record then return { ok = false, error = Lp(src, 'med.they_are_not_down') } end
    if record.stabilised and not S.stabiliseUnlimited then return { ok = false, error = Lp(src, 'med.already_packed') } end
    if distanceBetween(src, targetSrc) > (S.reviveDistance + 1.5) then
        return { ok = false, error = Lp(src, 'med.too_far_away') }
    end

    if S.stabiliseItem then
        if exports.bs_inventory:CountItem(src, S.stabiliseItem) < 1 then
            return { ok = false, error = Lp(src, 'med.you_have_no_bandage') }
        end
        exports.bs_inventory:RemoveItem(src, S.stabiliseItem, 1)
    end

    record.stabilised = true
    record.endsAt = record.endsAt + S.stabiliseBonus
    TriggerClientEvent('bs:medical:extend', targetSrc, S.stabiliseBonus)

    exports.bs_core:AwardAction(src, 'wound_treated')
    return { ok = true }
end)

-- Asked before the twelve second animation, so nobody kneels for nothing.
BSB.RegisterCallback('medical:dead', function(src)
    if not S.enabled then return { ok = false, error = 'off' } end
    if looksAliveAndWell(src, HARD_DEATH_GRACE_MS) then return { ok = false, error = 'not dead' } end
    if Down[src] then clearCarry(src) Down[src] = nil Player(src).state:set('bsDowned', false, true) end
    setDead(src, true)
    return { ok = true }
end)

BSB.RegisterCallback('medical:reviveCheck', function(src, targetSrc)
    targetSrc = tonumber(targetSrc)
    if targetSrc and Down[targetSrc] and Down[targetSrc].flat then return { ok = false, error = Lp(src, 'err_flatline') } end
    local canDead = S.reviveDead ~= false and targetSrc and Dead[targetSrc]
    if not targetSrc or not (Down[targetSrc] or canDead) then return { ok = false, error = Lp(src, 'med.they_are_not_down') } end
    if targetSrc == src then return { ok = false, error = Lp(src, 'med.not_on_yourself') } end
    if distanceBetween(src, targetSrc) > (S.reviveDistance + 1.5) then
        return { ok = false, error = Lp(src, 'med.get_closer') }
    end

    if S.reviveItem and exports.bs_inventory:CountItem(src, S.reviveItem) < 1 then
        return { ok = false, error = Lp(src, 'med.you_need_a_medkit') }
    end

    return { ok = true }
end)

-- Checked again on completion: distance, item, still down.
BSB.RegisterCallback('medical:revive', function(src, targetSrc)
    targetSrc = tonumber(targetSrc)
    if targetSrc and Down[targetSrc] and Down[targetSrc].flat then return { ok = false, error = Lp(src, 'err_flatline') } end
    local canDead = S.reviveDead ~= false and targetSrc and Dead[targetSrc]
    if targetSrc == src then return { ok = false, error = Lp(src, 'med.not_on_yourself') } end
    if not targetSrc or not (Down[targetSrc] or canDead) then return { ok = false, error = Lp(src, 'med.too_late_they_already_respawned') } end
    if distanceBetween(src, targetSrc) > (S.reviveDistance + 1.5) then
        return { ok = false, error = Lp(src, 'med.you_moved_away') }
    end

    if S.reviveItem then
        if exports.bs_inventory:CountItem(src, S.reviveItem) < 1 then
            return { ok = false, error = Lp(src, 'med.the_medkit_is_gone') }
        end
        exports.bs_inventory:RemoveItem(src, S.reviveItem, 1)
    end

    if Down[targetSrc] then
        finish(targetSrc, true)
    else
        -- On the death screen nothing has been wiped yet (that happens on respawn, in runHardDeath), so they get up with their kit.
        setDead(targetSrc, false)
        lastHardDeath[targetSrc] = nil
        if GetResourceState('bs_guard') == 'started' then pcall(function() exports.bs_guard:Allow(targetSrc, 'teleport', 15000) end) end
        TriggerClientEvent('bs:medical:revived', targetSrc)
    end
    exports.bs_core:AwardAction(src, 'player_revived')

    local healer = exports.bs_core:GetPlayer(src)
    local saved  = exports.bs_core:GetPlayer(targetSrc)
    print(('^2[BS MEDICAL]^7 %s revived %s'):format(
        healer and healer.name or src, saved and saved.name or targetSrc))

    return { ok = true }
end)

-- Getting yourself up with a medkit.

local SR = Medical.SelfRevive or {}

-- Spends the item (unless `alreadyConsumed`) and revives. Returns ok, err.
local function selfRevive(src, alreadyConsumed)
    if not SR.enabled then return false, Lp(src, 'med.you_cannot_get_yourself_up') end
    if not isDown(src) then return false, Lp(src, 'med.you_are_not_down') end
    if Down[src].flat then return false, Lp(src, 'med.no_pulse') end
    if not alreadyConsumed and SR.item then
        if exports.bs_inventory:CountItem(src, SR.item) < 1 then
            return false, Lp(src, 'med.you_have_no_medkit')
        end
        exports.bs_inventory:RemoveItem(src, SR.item, 1)
    end
    finish(src, true)
    local record = deaths[src]
    if record then record.wiped = true end
    local player = exports.bs_core:GetPlayer(src)
    print(('^2[BS MEDICAL]^7 %s patched themselves up'):format(player and player.name or src))
    return true
end

BSB.RegisterCallback('medical:selfRevive', function(src)
    local ok, err = selfRevive(src, false)
    return { ok = ok, error = err }
end)

-- For bs_inventory: the medkit was already consumed by inventory:use.
exports('SelfRevive', function(src) return (selfRevive(tonumber(src), true)) end)

-- What the downed HUD may offer: items in the bag and who can pick you up.
BSB.RegisterCallback('medical:options', function(src)
    if not isDown(src) then return { ok = false, error = Lp(src, 'med.you_are_not_down') } end
    local function count(item)
        if not item then return 0 end
        local ok, n = pcall(function() return exports.bs_inventory:CountItem(src, item) end)
        return ok and tonumber(n) or 0
    end
    return {
        ok         = true,
        bandages   = count(S.stabiliseItem),
        medkits    = SR.enabled and count(SR.item) or 0,
        stabilised = Down[src].stabilised,
    }
end)

-- Shot/hit by another player while down. Only honoured when executions are on, the attacker is a real player and close enough.
BSB.RegisterCallback('medical:executed', function(src, attacker)
    if not (Medical.PvP and Medical.PvP.allowExecution) then return { ok = false, error = 'off' } end
    attacker = tonumber(attacker)
    if not isDown(src) or not attacker or attacker == src or not GetPlayerName(attacker) then
        return { ok = false, error = 'invalid' }
    end
    if distanceBetween(src, attacker) > 300.0 then return { ok = false, error = 'too far' } end
    print(('^3[BS MEDICAL]^7 %s was finished off by %s'):format(src, attacker))
    finish(src, false)
    return { ok = true }
end)

-- Drag and carry

local C = Medical.Carry or {}

local function carryLevel(src)
    if GetResourceState('bs_skills') ~= 'started' then return 0 end
    local function has(id)
        local ok, r = pcall(function() return exports.bs_skills:HasPerk(src, id) end)
        return ok and r
    end
    if has('fireman_carry_3') then return 3 end
    if has('fireman_carry_2') then return 2 end
    if has('fireman_carry') then return 1 end
    return 0
end

BSB.RegisterCallback('medical:carryStart', function(src, targetSrc, mode)
    if not C.enabled then return { ok = false, error = Lp(src, 'med.dragging_is_switched_off') } end
    targetSrc = tonumber(targetSrc)
    if mode ~= 'drag' and mode ~= 'carry' then return { ok = false, error = 'bad mode' } end
    if not targetSrc or targetSrc == src or not isDown(targetSrc) then
        return { ok = false, error = Lp(src, 'med.they_are_not_down') }
    end
    if isDown(src) then return { ok = false, error = Lp(src, 'med.you_are_down_yourself') } end
    if Carrying[src] then return { ok = false, error = Lp(src, 'med.your_hands_are_full') } end
    if CarriedBy[targetSrc] then return { ok = false, error = Lp(src, 'med.someone_already_has_them') } end
    if CarriedBy[src] then return { ok = false, error = Lp(src, 'med.you_are_being_moved') } end
    if distanceBetween(src, targetSrc) > (C.serverMaxDist or 4.0) then
        return { ok = false, error = Lp(src, 'med.get_closer') }
    end

    local level = 0
    if mode == 'carry' then
        level = carryLevel(src)
        if level < 1 then
            return { ok = false, error = Lp(src, 'med.you_need_the_fireman_carry_skill_sur') }
        end
    end

    CarriedBy[targetSrc] = { carrier = src, mode = mode }
    Carrying[src] = targetSrc
    TriggerClientEvent('bs:medical:carry:victim', targetSrc, src, mode)
    return { ok = true, level = level }
end)

BSB.RegisterCallback('medical:carryStop', function(src)
    if not Carrying[src] and not CarriedBy[src] then return { ok = false, error = 'nothing to drop' } end
    clearCarry(src)
    return { ok = true }
end)

-- Asking for help: nearby players, squad and faction get a map ping.

local H = Medical.Help or {}
local lastHelp = {}

BSB.RegisterCallback('medical:callHelp', function(src)
    if not isDown(src) then return { ok = false, error = Lp(src, 'med.you_are_not_down') } end
    local now = os.time()
    local wait = (H.cooldown or 30) - (now - (lastHelp[src] or 0))
    if wait > 0 then return { ok = false, error = Lp(src, 'med.call_wait', { s = wait }) } end
    lastHelp[src] = now

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { ok = false, error = Lp(src, 'med.could_not_find_you') } end
    local at = GetEntityCoords(ped)

    local who = {}
    -- Squad first, then faction, then whoever is close enough to hear.
    if GetResourceState('bs_factions') == 'started' then
        local ok, members = pcall(function() return exports.bs_factions:GetSquadMembers(src) end)
        if ok and type(members) == 'table' then
            for _, m in ipairs(members) do if m.src then who[tonumber(m.src)] = 'squad' end end
        end
        local okF, fid = pcall(function() return exports.bs_factions:GetFaction(src) end)
        if okF and fid then
            for _, id in ipairs(GetPlayers()) do
                id = tonumber(id)
                if not who[id] then
                    local okO, other = pcall(function() return exports.bs_factions:GetFaction(id) end)
                    if okO and other == fid then who[id] = 'faction' end
                end
            end
        end
    end
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        if not who[id] then
            local p = GetPlayerPed(id)
            if p and p ~= 0 and #(GetEntityCoords(p) - at) <= (H.radius or 250.0) then who[id] = 'nearby' end
        end
    end
    who[src] = nil

    local player = exports.bs_core:GetPlayer(src)
    local name = (player and player.name) or GetPlayerName(src) or 'Someone'
    local n = 0
    for id, why in pairs(who) do
        n = n + 1
        TriggerClientEvent('bs:medical:helpPing', id, src, name, { x = at.x, y = at.y, z = at.z }, why)
    end
    return { ok = true, count = n }
end)

-- Cleanup and staff

-- Leaving while down counts as dying, so quitting does not keep the bag. bs_core and this resource both handle
local function pendingWipeKey(charId) return ('deathwipe:%s'):format(charId) end

local function wipeForDisconnect(src, charId)
    local record = Down[src]
    Down[src] = nil
    if not record or record.stabilised then return end
    if not S.wipeOnDeath or not charId then return end

    if GetResourceState('bs_darkzone') == 'started' then
        local okDz, kept = pcall(function() return exports.bs_darkzone:OnDeath(src) end)
        if okDz and kept == true then return end
    end
    SetResourceKvpInt(pendingWipeKey(charId), 1)
    print(('^3[BS MEDICAL]^7 %s left while down - treating it as a death'):format(src))

    if GetResourceState('bs_inventory') ~= 'started' then return end
    if Corpse and Corpse.FromDeath then pcall(Corpse.FromDeath, src) end
    TriggerEvent('bs:medical:death:beforeWipe', src)
    local ok, wiped = pcall(function() return exports.bs_inventory:WipeInventory(src) end)
    if ok and wiped then DeleteResourceKvp(pendingWipeKey(charId)) end
end

AddEventHandler('playerDropped', function()
    local src = source
    clearCarry(src)
    if Down[src] then
        local player = exports.bs_core:GetPlayer(src)
        wipeForDisconnect(src, player and player.charId)
    end
    lastHardDeath[src] = nil
    Dead[src] = nil
    lastHelp[src] = nil
    deaths[src] = nil
    DeadAt[src] = nil
end)

AddEventHandler('bs:hook:player:unloaded', function(player)
    if player and player.source and Dead[player.source] then setDead(player.source, false) end
    if player and player.source and Down[player.source] then
        wipeForDisconnect(player.source, player.charId)
        setStateBag(player.source, false)
    end
end)

-- The wipe that could not happen at disconnect happens here.
AddEventHandler('bs:hook:player:spawned', function(player)
    if not player or not player.source or not player.charId then return end
    local k = pendingWipeKey(player.charId)
    if GetResourceKvpInt(k) ~= 1 then return end
    if GetResourceState('bs_inventory') ~= 'started' then return end
    local ok, wiped = pcall(function() return exports.bs_inventory:WipeInventory(player.source) end)
    if ok and wiped then DeleteResourceKvp(k) end
end)

-- One revive, used by everyone: the dot, the console command and the admin menu. finish(target, true) only

-- Brings a player back whatever state they are in. Returns false only when there is no such player.
local function reviveNow(target)
    target = tonumber(target)
    if not target or not GetPlayerName(target) then return false end

    exports.bs_core:SetPlayerMeta(target,'survivorLink',nil)
    if Dead[target] then setDead(target, false) end
    if isDown(target) then
        -- The medic path. Clears Down, drops the state bag so Lp(src, 'med.treat_wounds') stops being offered, and tells the client.
        finish(target, true)
    else
        -- Down was never set (hard death or a plain heal-up). The client knows whether the ped needs resurrecting or just standing up.
        TriggerClientEvent('bs:medical:revived', target)
    end

    -- A revive undoes the death, so the next death gets its own wipe. Nothing restores items.
    local record = deaths[target]
    if record then record.wiped = true end

    -- Staff can pull someone out of a hard death too; without this the five second cooldown would refuse their next genuine one.
    lastHardDeath[target] = nil

    return true
end

RegisterCommand('revive', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.admin') then return end
    local target = tonumber(args[1]) or src
    if target == 0 then return print('usage: revive <playerId>') end

    if not reviveNow(target) then
        return print(('^1[BS MEDICAL]^7 revive: no player %d'):format(target))
    end
    print(('^2[BS MEDICAL]^7 staff revived %d'):format(target))
end, false)

exports('IsDowned', function(src) return isDown(tonumber(src)) end)
exports('Down', function(src) return goDown(tonumber(src)) end)

-- Defibrillator: only a stopped heart (flatline window) or a body still on the death screen.
function MedicalCanDefib(target)
    target = tonumber(target)
    if not target then return false end
    return (Down[target] and Down[target].flat) or Dead[target] == true
end
function MedicalDefibRevive(target) return reviveNow(target) end

-- The one revive, offered to bs_admin so the staff menu does not need ExecuteCommand.
exports('Revive', function(src) return reviveNow(src) end)

exports.bs_core:RegisterModule('medical', { side = 'server', version = '1.0.0', ready = true })

exports('LinkMedical',function(src,action)
    if GetInvokingResource()~='bs_survivor_link'then return end
    local down=Down[src]
    local life={status=Dead[src] and 'dead' or (down and 'downed' or 'alive'),endsAt=down and down.endsAt or nil,flat=down and down.flat or false}
    if action=='suspend'then
        clearCarry(src)
        if Dead[src]then beginDeath(src);wipeForDeath(src)end
        Down[src]=nil;lastHardDeath[src]=nil
        Player(src).state:set('bsFlatline',false,true)
        setStateBag(src,false);setDead(src,false)
    end
    return life
end)
exports('LinkReviveRules',function()
    if GetInvokingResource()~='bs_survivor_link'then return end
    return {item=S.reviveItem,duration=S.reviveTime,distance=S.reviveDistance,health=S.reviveHealth,bleedout=S.bleedoutTime,wipe=S.wipeOnDeath,hunger=S.respawnHunger,thirst=S.respawnThirst,catchHealth=S.catchHealth}
end)

exports('LinkRestore',function(src,life)
    if GetInvokingResource()~='bs_survivor_link' or type(life)~='table'then return end
    if life.status=='downed' and not life.flat and (life.endsAt or 0)>os.time()then
        Down[src]={endsAt=life.endsAt,stabilised=false};setStateBag(src,true)
        TriggerClientEvent('bs:medical:linkRestore',src,'downed',math.max(1,life.endsAt-os.time()))
    elseif life.status=='dead'or life.status=='downed'then
        setDead(src,true);TriggerClientEvent('bs:medical:linkRestore',src,'dead',0)
    end
end)
