-- bs_fighting - server: learned styles, sparring, PvP damage (capped and rate-limited), zombie trial credit.

FS = { knocked = {} }   -- [src] = { charId, styles, active, trials, spar, ... }; knocked[src] = when they went down
local S, P = Fighting.Settings, Fighting.PvP

local function now() return GetGameTimer() end

CreateThread(function()
    exports.oxmysql:execute_async([[
        CREATE TABLE IF NOT EXISTS `bs_fighting` (
            `character_id` INT NOT NULL PRIMARY KEY,
            `active` VARCHAR(24) NOT NULL DEFAULT 'untrained',
            `styles` TEXT NULL,
            `trials` TEXT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
    ]])
end)

local function decode(s)
    if type(s) ~= 'string' or s == '' then return {} end
    local ok, v = pcall(json.decode, s)
    return (ok and type(v) == 'table') and v or {}
end

function FS.Save(src)
    local st = FS[src]
    if not st or not st.charId then return end
    exports.oxmysql:execute([[
        INSERT INTO `bs_fighting` (`character_id`, `active`, `styles`, `trials`) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `active` = VALUES(`active`), `styles` = VALUES(`styles`), `trials` = VALUES(`trials`)
    ]], { st.charId, st.active, json.encode(st.styles), json.encode(st.trials) })
end

local function payload(st, learned)
    return { styles = st.styles, active = st.active, enabled = S.enabled, learned = learned }
end

function FS.Push(src, learned)
    local st = FS[src]
    if st then TriggerClientEvent('bs:fighting:state', src, payload(st, learned)) end
end

function FS.GrantStylePerk(src, styleId)
    if Fighting.Styles[styleId] and not Fighting.Styles[styleId].free then
        pcall(function() exports.bs_skills:GrantPerk(src, 'fs_' .. styleId) end)
    end
end

local function load(src, charId)
    local row = exports.oxmysql:single_async('SELECT `active`, `styles`, `trials` FROM `bs_fighting` WHERE `character_id` = ?', { charId })
    local st = { charId = charId, styles = { untrained = true }, active = S.defaultStyle or 'untrained', trials = {},
                 hits = {}, dmg = {}, lastStrike = 0, lastXp = 0, lastCounter = 0, hitOn = {}, nextTakedown = 0 }
    if row then
        for id, v in pairs(decode(row.styles)) do if v and Fighting.Styles[id] then st.styles[id] = true end end
        st.trials = decode(row.trials)
        if st.styles[row.active] then st.active = row.active end
    end
    FS[src] = st
    -- style perks live in bs_skills too (shown in the Skills tab); put back any a respec wiped
    CreateThread(function()
        Wait(4000)
        if FS[src] ~= st then return end
        for id in pairs(st.styles) do FS.GrantStylePerk(src, id) end
    end)
    Player(src).state:set('bsFightStyle', st.active, true)
    FS.Push(src)
end

AddEventHandler('bs:hook:player:loaded', function(player)
    if not player or not player.source then return end
    CreateThread(function() load(player.source, player.charId) end)
end)
AddEventHandler('bs:hook:player:unloaded', function(player)
    if player and player.source then FS[player.source] = nil end
end)
AddEventHandler('playerDropped', function() FS[source] = nil end)

-- resource restart: pick up everyone already in
CreateThread(function()
    Wait(1500)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local ok, p = pcall(function() return exports.bs_core:GetPlayer(src) end)
        if ok and p and p.charId then load(src, p.charId) end
    end
end)

BSB.RegisterCallback('fighting:state', function(src)
    local st = FS[src]
    if not st then return { styles = { untrained = true }, active = 'untrained', enabled = S.enabled } end
    return payload(st)
end)

-- Helpers

local function level(src)
    local ok, v = pcall(function() return exports.bs_skills:GetSkillLevel(src, 'fighting') end)
    return (ok and tonumber(v)) or 0
end

local function hasFn(src)
    return function(flag)
        local ok, v = pcall(function() return exports.bs_skills:HasPerk(src, flag) end)
        return ok and v == true
    end
end

function FS.XP(src, amount, gapMs)
    local st = FS[src]
    if not st or amount <= 0 then return end
    if gapMs and now() - (st.lastXp or 0) < gapMs then return end
    st.lastXp = now()
    pcall(function() exports.bs_skills:AddSkillXP(src, 'fighting', amount) end)
end

local function alive(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetEntityHealth(ped) <= 100 then return nil end
    if Player(src).state.bsDowned then return nil end
    return ped
end

local function inSafe(ped)
    if not P.blockInSafezones or GetResourceState('bs_zombies') ~= 'started' then return false end
    local c = GetEntityCoords(ped)
    local ok, inside = pcall(function() return exports.bs_zombies:InSafeZone(c.x, c.y) end)
    return ok and inside == true
end

-- moves this style can actually throw (any weapon class move is fine, the server can't see the weapon reliably)
local function allowed(st, moveId)
    local s = Fighting.Styles[st.active] or Fighting.Styles.untrained
    local p = moveId:sub(1, 3)
    if p == 'w1_' or p == 'w2_' or p == 'kn_' then return true end
    if moveId == s.heavy or moveId == s.kick or moveId == 'shove' then return true end
    if moveId == 'counter' then return true end
    if moveId == 'choke' then return s.choke == true end
    for _, m in ipairs(s.chain or {}) do if m == moveId then return true end end
    return false
end

-- rolling limits: hits per second and damage per 10 s
local function budget(st, dmg)
    local t = now()
    local h = st.hits
    while #h > 0 and t - h[1] > 1000 do table.remove(h, 1) end
    if #h >= P.maxHitsPerSecond then return 0 end
    local d = st.dmg
    local sum = 0
    for i = #d, 1, -1 do
        if t - d[i].t > 10000 then table.remove(d, i) else sum = sum + d[i].n end
    end
    dmg = math.min(dmg, P.maxDamagePer10s - sum)
    if dmg <= 0 then return 0 end
    h[#h + 1] = t
    d[#d + 1] = { t = t, n = dmg }
    return dmg
end

local choke
local function sendHit(target, from, dmg, extra)
    local data = { from = from, dmg = dmg, kind = 'hit' }
    for k, v in pairs(extra or {}) do data[k] = v end
    TriggerClientEvent('bs:fighting:hit', target, data)
end

function choke(src, target, extraTicks)
    CreateThread(function()
        Wait(600)
        for _ = 1, P.chokeTicks + (extraTicks or 0) do
            local a, b = alive(src), GetPlayerPed(target)
            if not S.enabled or not P.enabled or not a or not b or b == 0 or GetEntityHealth(b) <= 100 then return end
            if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(target) or inSafe(a) or inSafe(b) then return end
            if #(GetEntityCoords(a) - GetEntityCoords(b)) > 2.2 then return end
            sendHit(target, src, P.chokeDamage, { kind = 'choke', react = 'none' })
            Wait(math.floor((P.chokeMs or 4200) / (P.chokeTicks + (extraTicks or 0) + 1)))
        end
    end)
end

-- PvP

RegisterNetEvent('bs:fighting:hitPlayer', function(target, moveId, combo, counter, charge, tired)
    local src = source
    local st = FS[src]
    target = tonumber(target)
    if not S.enabled or not P.enabled or not st or not target or target == src then return end
    if type(moveId) ~= 'string' or not Fighting.Moves[moveId] or not allowed(st, moveId) then return end
    local a, b = alive(src), alive(target)
    if not a or not b then return end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(target) then return end
    if #(GetEntityCoords(a) - GetEntityCoords(b)) > P.maxRange then return end
    if inSafe(a) or inSafe(b) then return end

    local has = hasFn(src)
    local move = Fighting.Moves[moveId]

    if moveId == 'choke' then
        if now() < (st.nextChoke or 0) then return end
        st.nextChoke = now() + (P.chokeMs or 4200) + 2000
        TriggerClientEvent('bs:fighting:hit', target, { from = src, dmg = 0, kind = 'choke', react = 'choke' })
        choke(src, target, has('grp_choke') and 2 or 0)
        FS.XP(src, 4, 2000)
        return
    end

    -- a counter is only believed shortly after a parry or a walker escape the server saw
    counter = counter == true and now() - (st.lastCounter or 0) < 1500
    if counter then st.lastCounter = 0 end
    charge = tonumber(charge)
    if charge then charge = math.max(0, math.min(1, charge)) end

    local dmg = Fighting.Math.Damage(moveId, st.active, level(src), has, math.min(6, math.max(1, tonumber(combo) or 1)), counter, charge, tired == true)
    dmg = budget(st, math.min(dmg, P.maxDamagePerHit))
    if dmg <= 0 then return end

    local react = move.react or 'stumble'
    local sdef = Fighting.Styles[st.active] or {}
    if sdef.weaponDown and moveId:find('_heavy', 1, true) then react = 'down' end
    if charge and charge < 0.5 and (react == 'down' or react == 'throw') then react = 'stagger' end
    if tired == true and (react == 'down' or react == 'throw') then react = 'stagger' end
    local force = (move.push or 0) * ((moveId == 'throw' and has('grp_throw')) and 1.5 or 1.0)
    if react == 'down' or react == 'throw' then FS.knocked[target] = now() end

    st.hitOn[target] = now()
    sendHit(target, src, dmg, { react = react, force = force })
    FS.XP(src, S.xpPlayerHit, 2000)
end)

-- stomp on a player we (or anyone) just knocked down
RegisterNetEvent('bs:fighting:stomp', function(target)
    local src = source
    local st = FS[src]
    target = tonumber(target)
    if not S.enabled or not P.enabled or not st or not target or target == src then return end
    if now() - (FS.knocked[target] or 0) > (S.stompMs or 1800) + 1500 then return end
    local a, b = alive(src), GetPlayerPed(target)
    if not a or not b or b == 0 or GetEntityHealth(b) <= 100 then return end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(target) or inSafe(b) then return end
    if #(GetEntityCoords(a) - GetEntityCoords(b)) > S.stompRange + 1.2 or inSafe(a) then return end
    FS.knocked[target] = 0
    local dmg = budget(st, P.stompDamage)
    if dmg > 0 then sendHit(target, src, dmg, { kind = 'stomp', react = 'none' }) end
end)

-- reaction on a walker someone else owns: forward it to the owner
local reactGate = {}
RegisterNetEvent('bs:fighting:react', function(netId, kind, force, dx, dy)
    local src = source
    if not S.enabled or type(kind) ~= 'string' then return end
    if kind ~= 'stumble' and kind ~= 'stagger' and kind ~= 'down' and kind ~= 'throw' then return end
    local t = now()
    local g = reactGate[src]
    if not g or t - g.at > 1000 then g = { at = t, n = 0 }; reactGate[src] = g end
    g.n = g.n + 1
    if g.n > 8 then return end
    local ent = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not ent or ent == 0 or not DoesEntityExist(ent) or GetEntityType(ent) ~= 1 or IsPedAPlayer(ent) then return end
    local a = GetPlayerPed(src)
    if not a or a == 0 or #(GetEntityCoords(a) - GetEntityCoords(ent)) > 4.5 then return end
    local owner = NetworkGetEntityOwner(ent)
    if not owner or owner <= 0 or owner == src then return end
    force = math.max(0, math.min(14.0, tonumber(force) or 0))
    TriggerClientEvent('bs:fighting:reactOwned', owner, tonumber(netId), kind, force, tonumber(dx) or 0.0, tonumber(dy) or 0.0)
end)
AddEventHandler('playerDropped', function() reactGate[source] = nil end)

-- the victim says it parried: only honoured if that attacker really just hit them
RegisterNetEvent('bs:fighting:parried', function(attacker, what)
    local src = source
    attacker = tonumber(attacker)
    local at = attacker and FS[attacker]
    if not at or not FS[src] then return end
    if now() - (at.hitOn[src] or 0) > 1200 then return end
    at.hitOn[src] = nil
    FS[src].lastCounter = now()
    -- only the defender's real style decides what a parry does
    local d = Fighting.Styles[FS[src].active] or {}
    what = d.parryDo == what and what or 'none'
    TriggerClientEvent('bs:fighting:staggered', attacker, what)
    FS.XP(src, 3, 1500)
end)

RegisterNetEvent('bs:fighting:escaped', function()
    local st = FS[source]
    if st then st.lastCounter = now(); FS.XP(source, 3, 3000) end
end)

-- takedown from behind on a player: geometry checked here, not trusted from the client
RegisterNetEvent('bs:fighting:takedown', function(target)
    local src = source
    local st = FS[src]
    target = tonumber(target)
    if not S.enabled or not P.enabled or not st or not target or target == src then return end
    if now() < st.nextTakedown or not (Fighting.Styles[st.active] or {}).takedowns then return end
    local a, b = alive(src), alive(target)
    if not a or not b or inSafe(a) or inSafe(b) then return end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(target) then return end
    local pa, pb = GetEntityCoords(a), GetEntityCoords(b)
    local d = pa - pb
    local len = #(vector2(d.x, d.y))
    if len > S.takedownRange + 1.0 or len < 0.01 then return end
    local h = math.rad(GetEntityHeading(b))
    local fx, fy = -math.sin(h), math.cos(h)
    if (fx * d.x + fy * d.y) / len > (S.takedownBehindDot or -0.25) + 0.2 then return end
    st.nextTakedown = now() + math.floor(S.takedownCooldownMs * 0.5)
    local dmg = budget(st, P.takedownDamage)
    if dmg <= 0 then return end
    FS.knocked[target] = now()
    sendHit(target, src, dmg, { kind = 'takedown', react = 'down', force = 3.0 })
    FS.XP(src, 6, 1000)
end)

-- Styles

RegisterNetEvent('bs:fighting:setStyle', function(id)
    local src = source
    local st = FS[src]
    if not st or type(id) ~= 'string' or not st.styles[id] then
        if st then FS.Push(src) end
        return
    end
    st.active = id
    Player(src).state:set('bsFightStyle', id, true)
    FS.Save(src)
end)

function FS.Learn(src, styleId)
    local st = FS[src]
    if not st or not Fighting.Styles[styleId] then return false end
    st.styles[styleId] = true
    st.active = styleId
    st.trials[styleId] = st.trials[styleId] or { n = 0 }
    FS.GrantStylePerk(src, styleId)
    Player(src).state:set('bsFightStyle', styleId, true)
    FS.Save(src)
    FS.Push(src, styleId)
    return true
end

-- Walkers: strike credit for trials and XP. The damage itself already went through bs_zombies.

RegisterNetEvent('bs:fighting:struck', function(walkerId, moveId)
    local st = FS[source]
    if not st or type(moveId) ~= 'string' or not Fighting.Moves[moveId] then return end
    st.lastStrike = now()
    st.lastStrikeStyle = st.active
    FS.XP(source, S.xpZombieStrike, 1500)
end)

AddEventHandler('bs:zombies:killed', function(src, _, _, _, _)
    src = tonumber(src)
    local st = src and FS[src]
    if not st or now() - (st.lastStrike or 0) > Fighting.Trials.creditMs then return end
    FS.XP(src, S.xpZombieKill)
    local style = st.lastStrikeStyle
    local trial = style and st.trials[style]
    if trial and not trial.done and Fighting.Styles[style] and not Fighting.Styles[style].free then
        local need = Fighting.IsAdvanced(style) and Fighting.Trials.advancedKills or Fighting.Trials.basicKills
        trial.n = math.min(need, (trial.n or 0) + 1)
        if trial.n >= need then
            trial.done = true
            TriggerClientEvent('bs:ui:notify', src, { type = 'success', message = Lp(src, 'trial.done', { style = Lp(src, 'style.' .. style) }), duration = 5000 })
        end
        FS.Save(src)
    end
end)

-- Staff test shortcuts (admin only)

local function staff(src) return src == 0 or IsPlayerAceAllowed(src, 'bs.admin') end

RegisterCommand('fightlearn', function(src, args)
    if not staff(src) then return end
    local target = tonumber(args[2]) or src
    local what = tostring(args[1] or 'all')
    if not FS[target] then return end
    for id, s in pairs(Fighting.Styles) do
        if what == 'all' or what == id then
            FS[target].styles[id] = true
            FS[target].trials[id] = FS[target].trials[id] or { n = 0 }
            FS.GrantStylePerk(target, id)
        end
    end
    FS.Save(target); FS.Push(target)
    print(('[bs_fighting] %s learned %s'):format(target, what))
end, false)

-- loads every clip on the caller's client and prints the missing ones
RegisterCommand('fightanims', function(src)
    if src == 0 or not staff(src) then return end
    TriggerClientEvent('bs:fighting:animCheck', src)
end, false)

-- /ffcliptest [all | class | dict clip]: plays freeflow clips on the caller with several flag sets (F8)
RegisterCommand('ffcliptest', function(src, args)
    if src == 0 or not staff(src) then return end
    TriggerClientEvent('bs:fighting:cliptest', src, args[1], args[2])
end, false)

-- /fightforget <style> [playerId]: staff, forget one style
RegisterCommand('fightforget', function(src, args)
    if not staff(src) then return end
    local id = tostring(args[1] or '')
    local target = tonumber(args[2]) or src
    local st = FS[target]
    if not st or id == '' or id == 'untrained' or not Fighting.Styles[id] then return end
    st.styles[id], st.trials[id] = nil, nil
    if st.active == id then st.active = 'untrained' end
    pcall(function() exports.bs_skills:RevokePerk(target, 'fs_' .. id) end)
    FS.Save(target); FS.Push(target)
end, false)

RegisterCommand('fightreset', function(src, args)
    if not staff(src) then return end
    local target = tonumber(args[1]) or src
    local st = FS[target]
    if not st then return end
    st.styles, st.trials, st.active = { untrained = true }, {}, 'untrained'
    for id in pairs(Fighting.Styles) do pcall(function() exports.bs_skills:RevokePerk(target, 'fs_' .. id) end) end
    FS.Save(target); FS.Push(target)
end, false)

exports('LearnStyle', function(src, styleId) return FS.Learn(tonumber(src), styleId) end)
exports('GetStyles', function(src) local st = FS[tonumber(src)]; return st and st.styles or {} end)
exports('GetActiveStyle', function(src) local st = FS[tonumber(src)]; return st and st.active or 'untrained' end)

-- Freeflow (v3). Walker damage already went through bs_zombies; these give XP, trial credit and PvP.

local FFS, FFP = Freeflow.Settings, Freeflow.PvP
local ffKinds = { light = FFS.xpLight, heavy = FFS.xpHeavy, counter = FFS.xpCounter }

RegisterNetEvent('bs:fighting:ffLanded', function(walkerId, kind)
    local src = source
    local st = FS[src]
    if not st or not S.enabled or type(kind) ~= 'string' or not ffKinds[kind] then return end
    st.lastStrike = now()
    st.lastStrikeStyle = st.active
    FS.XP(src, ffKinds[kind], FFS.xpGapMs)
end)

RegisterNetEvent('bs:fighting:ffFinisher', function(walkerId)
    local src = source
    local st = FS[src]
    if not st or not S.enabled then return end
    if now() - (st.lastFinisher or 0) < 1100 then return end
    st.lastFinisher = now()
    st.lastStrike = now()
    st.lastStrikeStyle = st.active
    FS.XP(src, FFS.xpFinisher)
end)

-- Player hit: same checks and budget as v1. The victim's own client plays the reaction.
RegisterNetEvent('bs:fighting:ffHitPlayer', function(target, kind, combo)
    local src = source
    local st = FS[src]
    target = tonumber(target)
    if not S.enabled or not P.enabled or not FFP.enabled or not st or not target or target == src then return end
    if kind ~= 'light' and kind ~= 'heavy' then return end
    local a, b = alive(src), alive(target)
    if not a or not b then return end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(target) then return end
    if #(GetEntityCoords(a) - GetEntityCoords(b)) > (FFP.maxRange or P.maxRange) then return end
    if inSafe(a) or inSafe(b) then return end
    local base = (FFP.damage or {})[kind] or 0
    combo = math.min(6, math.max(1, tonumber(combo) or 1))
    local dmg = base * (1.0 + level(src) * (S.damagePerLevel or 0)) * (1.0 + (combo - 1) * 0.05)
    dmg = budget(st, math.min(math.floor(dmg + 0.5), P.maxDamagePerHit))
    if dmg <= 0 then return end
    st.hitOn[target] = now()
    TriggerClientEvent('bs:fighting:ffHit', target, { from = src, dmg = dmg, kind = kind })
    FS.XP(src, S.xpPlayerHit, 2000)
end)

-- Shared banned clips: a client whose bone check catches a T-pose reports the clip; everyone avoids it.
local validClip = {}
for _, set in pairs(Freeflow.Clips) do
    for _, v in pairs(set) do
        if type(v) == 'table' then
            local list = v.dict and { v } or v
            for _, c in pairs(list) do
                if type(c) == 'table' and c.dict then
                    for k, name in pairs(c) do
                        if type(name) == 'string' and k ~= 'dict' then validClip[c.dict .. '/' .. name] = true end
                    end
                end
            end
        end
    end
end

local clipBans = {}
pcall(function()
    local v = json.decode(GetResourceKvpString('ff_clip_bans') or '')
    if type(v) == 'table' then clipBans = v end
end)
local banGate = {}

RegisterNetEvent('bs:fighting:clipBansGet', function()
    TriggerClientEvent('bs:fighting:clipBans', source, clipBans)
end)

RegisterNetEvent('bs:fighting:clipBad', function(key)
    local src = source
    if type(key) ~= 'string' or not validClip[key] or clipBans[key] then return end
    local g = banGate[src] or { at = 0, n = 0 }
    banGate[src] = g
    if now() - g.at < 5000 or g.n >= 20 then return end
    g.at, g.n = now(), g.n + 1
    clipBans[key] = true
    SetResourceKvp('ff_clip_bans', json.encode(clipBans))
    print(('[bs_fighting] clip %s banned for everyone (reported by %s)'):format(key, src))
    TriggerClientEvent('bs:fighting:clipBans', -1, { [key] = true })
end)
AddEventHandler('playerDropped', function() banGate[source] = nil end)

-- /ffclipunban <dict/clip | all>: staff, clears the shared ban (clients keep their own until /ffclipunban runs there too)
RegisterCommand('ffclipunban', function(src, args)
    if not staff(src) then return end
    local key = tostring(args[1] or '')
    if key == 'all' then clipBans = {} elseif clipBans[key] then clipBans[key] = nil else return end
    SetResourceKvp('ff_clip_bans', json.encode(clipBans))
    TriggerClientEvent('bs:fighting:clipUnban', -1, key)
    print(('[bs_fighting] clip ban cleared: %s'):format(key))
end, false)
