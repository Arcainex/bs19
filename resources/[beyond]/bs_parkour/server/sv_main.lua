-- Server half: checks every move report before it pays XP, trainers, escapes, admin commands.

local S = Parkour.Settings
local State = {}
PKS = { State = State }

local function now() return os.time() end
local function ms() return GetGameTimer() end

local function isAdmin(src)
    if src == 0 then return true end
    for _, ace in ipairs(S.adminAces or {}) do
        if IsPlayerAceAllowed(src, ace) then return true end
    end
    return false
end
PKS.IsAdmin = isAdmin

function PKS.CharId(src)
    local ok, p = pcall(function() return exports.bs_core:GetPlayer(src) end)
    return ok and p and p.charId or nil
end

local function st(src)
    local s = State[src]
    if not s then
        s = { last = {}, minute = 0, minuteXp = 0 }
        State[src] = s
    end
    return s
end

function PKS.HasPerk(src, perk)
    local ok, v = pcall(function() return exports.bs_skills:HasPerk(src, perk) end)
    return ok and v == true
end

local function level(src)
    local ok, v = pcall(function() return exports.bs_skills:GetSkillLevel(src, 'parkour') end)
    return ok and tonumber(v) or 0
end

local function notify(src, kind, key, vars)
    TriggerClientEvent('bs:ui:notify', src, { type = kind, message = Lp(src, key, vars), duration = 4000 })
end
PKS.Notify = notify

-- XP with a per-minute cap, so a stuck macro cannot farm
local function grant(src, amount, bypassCap)
    amount = math.floor((amount or 0) * (S.xpMult or 1.0))
    if amount <= 0 then return 0 end
    local s = st(src)
    local minute = math.floor(now() / 60)
    if s.minute ~= minute then s.minute, s.minuteXp = minute, 0 end
    if not bypassCap then
        local room = (S.xpPerMinuteCap or 160) - s.minuteXp
        if room <= 0 then return 0 end
        amount = math.min(amount, room)
    end
    s.minuteXp = s.minuteXp + amount
    pcall(function() exports.bs_skills:AddSkillXP(src, 'parkour', amount) end)
    return amount
end
PKS.Grant = grant

local function vec(t)
    if type(t) ~= 'table' then return nil end
    local x, y, z = tonumber(t[1]), tonumber(t[2]), tonumber(t[3])
    if not x or not y or not z then return nil end
    return vector3(x, y, z)
end

RegisterNetEvent('bs:parkour:move', function(kind, from, to)
    local src = source
    if not S.enabled or type(kind) ~= 'string' then return end
    local move = Parkour.Moves[kind]
    local tier = Parkour.MoveTier[kind]
    if not move or not move.enabled or not tier then return end
    -- Basic moves are open to everyone; advanced ones need the level or the advanced perk
    local P3 = Parkour.Pk3 or {}
    if (P3.AdvancedMoves or {})[kind] and level(src) < (P3.advancedLevel or 3) and not PKS.HasPerk(src, Parkour.TierPerk.advanced) then return end

    local ped = GetPlayerPed(src)
    if ped == 0 or GetVehiclePedIsIn(ped, false) ~= 0 or GetEntityHealth(ped) <= 0 then return end
    local s = st(src)
    local t = ms()
    if t - (s.last[kind] or 0) < (move.cooldown or 0) * 0.6 then return end

    from, to = vec(from), vec(to)
    if not from or not to then return end
    local here = GetEntityCoords(ped)
    if #(here - to) > 8.0 or #(from - to) > 25.0 then return end
    if (kind == 'climb' or kind == 'climbHigh') and to.z - from.z < 0.6 then return end
    if (kind == 'vault' or kind == 'bonnet') and #(vector3(to.x, to.y, 0.0) - vector3(from.x, from.y, 0.0)) < 0.8 then return end

    s.last[kind] = t
    grant(src, move.xp)
    if PKS.Progress then PKS.Progress(src, 'move', kind) end
end)

RegisterNetEvent('bs:parkour:chase', function()
    local src = source
    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    local s = st(src)
    s.chaseAt, s.chasePos = now(), GetEntityCoords(ped)
end)

RegisterNetEvent('bs:parkour:escape', function()
    local src = source
    if not S.enabled or not S.escapeEnabled then return end
    if not PKS.HasPerk(src, 'pk_basics') then return end
    local s = st(src)
    local ped = GetPlayerPed(src)
    if ped == 0 or not s.chaseAt or not s.chasePos then return end
    local t = now()
    local elapsed = t - s.chaseAt
    local from = s.chasePos
    s.chaseAt, s.chasePos = nil, nil
    if elapsed < (S.lostSeconds or 6) * 0.5 or elapsed > 900 then return end
    if t - (s.lastEscape or 0) < (S.escapeCooldown or 60) then return end
    if #(GetEntityCoords(ped) - from) < (S.escapeMinDistance or 35) * 0.8 then return end
    s.lastEscape = t
    local xp = S.escapeXp or 40
    if PKS.HasPerk(src, 'pk_breakaway') then xp = xp * 1.3 end
    local got = grant(src, xp, true)
    notify(src, 'success', 'pk.escaped', { xp = got })
    if PKS.Progress then PKS.Progress(src, 'escape') end
end)

-- Trainer tiers are kept here as well, so a perk reset in the skills tab does not undo training
local function tierKey(cid) return ('parkour_tier_%s'):format(cid) end
function PKS.Tier(src)
    local cid = PKS.CharId(src)
    return cid and GetResourceKvpString(tierKey(cid)) or nil
end
local function setTier(src, tier)
    local cid = PKS.CharId(src)
    if cid then SetResourceKvp(tierKey(cid), tier) end
end

local function restoreTraining(src)
    local tier = PKS.Tier(src)
    if not tier then return end
    if not PKS.HasPerk(src, 'pk_basics') then pcall(function() exports.bs_skills:GrantPerk(src, 'pk_basics') end) end
    if tier == 'advanced' and not PKS.HasPerk(src, 'pk_advanced') then pcall(function() exports.bs_skills:GrantPerk(src, 'pk_advanced') end) end
end

AddEventHandler('bs:hook:player:loaded', function(player)
    if not player or not player.source then return end
    local src = player.source
    State[src] = nil
    SetTimeout(4000, function() restoreTraining(src) end)
end)
AddEventHandler('playerDropped', function() State[source] = nil end)
CreateThread(function()
    while true do
        Wait(60000)
        for _, id in ipairs(GetPlayers()) do restoreTraining(tonumber(id)) end
    end
end)

function PKS.Trainer(id)
    for _, t in ipairs(Parkour.Trainers) do if t.id == id then return t end end
    return nil
end

function PKS.NearTrainer(src, t)
    local ped = GetPlayerPed(src)
    if ped == 0 or not t then return false end
    local p = GetEntityCoords(ped)
    local d = #(vector3(p.x, p.y, 0.0) - vector3(t.x, t.y, 0.0))
    return d <= (Parkour.TrainerRange or 6.0) + 2.0 and math.abs(p.z - t.z) < 30.0
end

local function pay(src, amount, reason)
    if (amount or 0) <= 0 then return true end
    local ok, paid = pcall(function() return exports.bs_core:RemoveMoney(src, 'cash', amount, reason) end)
    return ok and paid
end

BSB.RegisterCallback('parkour:learn', function(src, trainerId)
    if not S.enabled then return { ok = false, msg = Lp(src, 'pk.off') } end
    local t = PKS.Trainer(tostring(trainerId))
    if not PKS.NearTrainer(src, t) then return { ok = false, msg = Lp(src, 'pk.too_far') } end
    local basics = PKS.HasPerk(src, 'pk_basics')
    if t.tier == 'basic' then
        if basics then return { ok = false, msg = Lp(src, 'pk.know_basics') } end
        if not pay(src, S.basicCost, 'parkour_training') then return { ok = false, msg = Lp(src, 'pk.no_money', { n = S.basicCost }) } end
        pcall(function() exports.bs_skills:GrantPerk(src, 'pk_basics') end)
        setTier(src, 'basic')
        return { ok = true, msg = Lp(src, 'pk.learned_basic') }
    end
    if PKS.HasPerk(src, 'pk_advanced') then return { ok = false, msg = Lp(src, 'pk.know_advanced') } end
    if not basics then return { ok = false, msg = Lp(src, 'pk.need_basics') } end
    if level(src) < (S.advancedLevel or 5) then return { ok = false, msg = Lp(src, 'pk.need_level', { n = S.advancedLevel }) } end
    if S.advancedNeedsTrial and PKS.TrialDone and not PKS.TrialDone(src, 'pk_rooftops') then
        return { ok = false, msg = Lp(src, 'pk.need_trial', { title = Lp(src, 'ch.pk_rooftops.t') }) }
    end
    if not pay(src, S.advancedCost, 'parkour_training') then return { ok = false, msg = Lp(src, 'pk.no_money', { n = S.advancedCost }) } end
    pcall(function() exports.bs_skills:GrantPerk(src, 'pk_advanced') end)
    setTier(src, 'advanced')
    return { ok = true, msg = Lp(src, 'pk.learned_advanced') }
end)

-- Admin

local function parkourPerks()
    local out = {}
    local ok, list = pcall(function() return exports.bs_skills:PerkCatalogue() end)
    for _, p in ipairs(ok and list or {}) do if p.tree == 'parkour' then out[#out + 1] = p.id end end
    return out
end

local function reply(src, msg)
    if src == 0 then print(msg) else TriggerClientEvent('chat:addMessage', src, { args = { 'Parkour', msg } }) end
end

-- /parkourlevel <playerId> <level>
RegisterCommand('parkourlevel', function(src, args)
    if not isAdmin(src) then return end
    local target, lvl = tonumber(args[1]), tonumber(args[2])
    if not target or not lvl then return reply(src, 'usage: parkourlevel <playerId> <0-20>') end
    local ok = exports.bs_skills:SetSkillLevel(target, 'parkour', lvl)
    reply(src, ok and ('parkour level %d set for %d'):format(lvl, target) or 'failed (character not loaded?)')
end, false)

-- /parkourperk <playerId> <perkId|basic|advanced|all|reset>
RegisterCommand('parkourperk', function(src, args)
    if not isAdmin(src) then return end
    local target, what = tonumber(args[1]), args[2]
    if not target or not what then return reply(src, 'usage: parkourperk <playerId> <perkId|basic|advanced|all|reset>') end
    local list
    if what == 'basic' then list = { 'pk_basics' } setTier(target, 'basic')
    elseif what == 'advanced' then list = { 'pk_basics', 'pk_advanced' } setTier(target, 'advanced')
    elseif what == 'all' then list = parkourPerks() setTier(target, 'advanced')
    elseif what == 'reset' then
        local cid = PKS.CharId(target)
        if cid then DeleteResourceKvp(tierKey(cid)) end
        for _, id in ipairs(parkourPerks()) do pcall(function() exports.bs_skills:RevokePerk(target, id) end) end
        return reply(src, 'parkour training and perks removed')
    else list = { what } end
    local n = 0
    for _, id in ipairs(list) do
        local ok = exports.bs_skills:GrantPerk(target, id)
        if ok then n = n + 1 end
    end
    reply(src, ('%d parkour perk(s) granted to %d'):format(n, target))
end, false)

-- /parkourtrainer [id or number]: list trainers, or teleport to one
RegisterCommand('parkourtrainer', function(src, args)
    if not isAdmin(src) or src == 0 then return end
    local key = args[1]
    if not key then
        for i, t in ipairs(Parkour.Trainers) do reply(src, ('%d %s (%s) %s'):format(i, t.id, t.tier, t.label)) end
        return
    end
    local t = Parkour.Trainers[tonumber(key) or 0] or PKS.Trainer(key)
    if not t then return reply(src, 'unknown trainer') end
    TriggerClientEvent('bs:core:safeTp', src, t.x + 1.5, t.y + 1.5, t.z)
end, false)

-- /parkouranims [kind]: prints which animation clips load on your client (F8), and plays one if a kind is given
RegisterCommand('parkouranims', function(src, args)
    if src == 0 or not isAdmin(src) then return end
    TriggerClientEvent('bs:parkour:animcheck', src, args[1])
end, false)

-- /pkmeasure <dict> <clip> | dump: measures a clip's movement on your client and prints a config line (F8)
RegisterCommand('pkmeasure', function(src, args)
    if src == 0 or not isAdmin(src) then return end
    TriggerClientEvent('bs:parkour:measure', src, args[1], args[2])
end, false)

-- /pkcliptest <dict> <clip>: plays a clip with each flag set and reports whether the body really animates (F8)
RegisterCommand('pkcliptest', function(src, args)
    if src == 0 or not isAdmin(src) then return end
    TriggerClientEvent('bs:parkour:cliptest', src, args[1], args[2])
end, false)

exports('IsTrained', function(src, tier) return PKS.HasPerk(src, Parkour.TierPerk[tier or 'basic'] or 'pk_basics') end)

exports.bs_core:RegisterModule('parkour', { side = 'server', version = '1.0.0', ready = true })
