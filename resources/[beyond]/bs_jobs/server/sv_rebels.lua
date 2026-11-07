-- bs_jobs rebels: hands up, kidnapping with ransom, robbery at gunpoint and smuggler pings.
-- Anti-grief: never in a safezone, the same victim once per victimCooldownMin per kind, ransom cap, auto release.

local S = Jobs.Settings
local INV = exports.bs_inventory

-- Victim cooldowns, per kind ('rob', 'kidnap', 'chop'). In memory: a restart clears them.
local Victims = {}   -- [cid] = { [kind] = os.time }
function J.VictimFree(cid, kind)
    local t = Victims[tonumber(cid) or -1]
    t = t and t[kind]
    return not t or J.Now() - t >= (tonumber(S.victimCooldownMin) or 120) * 60
end
function J.MarkVictim(cid, kind)
    cid = tonumber(cid)
    if not cid then return end
    Victims[cid] = Victims[cid] or {}
    Victims[cid][kind] = J.Now()
end

RegisterNetEvent('bs:jobs:handsUp', function(on)
    Player(source).state:set('bsHandsUp', on == true, true)
end)

local function pstate(src) return Player(src).state end
local function close(a, b, dist)
    local pa, pb = J.PedPos(a), J.PedPos(b)
    return pa and pb and #(pa - pb) <= (dist or 3.0)
end
local function safeEither(a, b)
    local pa, pb = J.PedPos(a), J.PedPos(b)
    return (pa and J.InSafeZone(pa.x, pa.y)) or (pb and J.InSafeZone(pb.x, pb.y))
end
-- Shared checks for robbing and tying someone up.
local function targetCheck(src, target, kind)
    target = tonumber(target)
    if not target or target == src or not GetPlayerName(target) then return nil, Lp(src, 'err.not_there') end
    local cid = J.CharId(target)
    if not cid then return nil, Lp(src, 'err.not_there') end
    if not close(src, target, 3.0) then return nil, Lp(src, 'err.too_far') end
    if safeEither(src, target) then return nil, Lp(src, 'err.safezone') end
    if J.Faction(target) and J.Faction(target) == J.Faction(src) then return nil, Lp(src, 'err.own_faction') end
    local st = pstate(target)
    if not (st.bsHandsUp or st.bsCuffed or st.bsDowned) then return nil, Lp(src, 'err.hands_down') end
    if kind and not J.VictimFree(cid, kind) then return nil, Lp(src, 'err.victim_cooldown') end
    return target, nil, cid
end

--------------------------------------------------------------------------------
-- Kidnapping
--------------------------------------------------------------------------------

local Captives = {}   -- [victimSrc] = { by, byCid, cid, fid, at, hooded, carried, ransom }
J.Captives = Captives

local function free(victim, why)
    local c = Captives[victim]
    if not c then return end
    Captives[victim] = nil
    if GetPlayerName(victim) then
        local st = pstate(victim)
        st:set('bsCuffed', nil, true)
        st:set('bsHooded', nil, true)
        st:set('bsCarriedBy', nil, true)
        J.Notify(victim, 'success', 'n.released')
    end
    if c.by and GetPlayerName(c.by) then J.Notify(c.by, 'info', 'n.captive_released') end
    J.Log(c.by, 'release', ('%s %s'):format(tostring(c.cid), why or ''))
end

BSB.RegisterCallback('jobs:kid:tie', function(src, target)
    if not J.Does(src, 'kidnap') then return { ok = false, error = Lp(src, 'err.wrong_job') } end
    local t, err, cid = targetCheck(src, target, 'kidnap')
    if not t then return { ok = false, error = err } end
    if Captives[t] then return { ok = false, error = Lp(src, 'err.already_held') } end
    if not INV:RemoveItem(src, 'zip_ties', 1) then return { ok = false, error = Lp(src, 'err.need_item', { item = INV:ItemLabel('zip_ties', src) }) } end
    Captives[t] = { by = src, byCid = J.CharId(src), cid = cid, fid = J.Faction(t), at = J.Now() }
    pstate(t):set('bsCuffed', true, true)
    J.MarkVictim(cid, 'kidnap')
    J.Notify(t, 'error', 'n.you_are_tied')
    J.Progress(src, 'kidnap', 1)
    J.Log(src, 'kidnap', ('victim %d'):format(cid))
    return { ok = true }
end)

local function myCaptive(src, target)
    if type(target) == 'table' then target = target.target end
    target = tonumber(target)
    local c = target and Captives[target]
    if not c or c.by ~= src then return nil end
    return target, c
end

BSB.RegisterCallback('jobs:kid:hood', function(src, target)
    local t, c = myCaptive(src, target)
    if not t or not close(src, t, 3.0) then return { ok = false, error = Lp(src, 'err.not_there') } end
    if c.hooded then
        c.hooded = false
        INV:GiveItem(src, 'head_sack', 1)
    else
        if not INV:RemoveItem(src, 'head_sack', 1) then return { ok = false, error = Lp(src, 'err.need_item', { item = INV:ItemLabel('head_sack', src) }) } end
        c.hooded = true
    end
    pstate(t):set('bsHooded', c.hooded or nil, true)
    return { ok = true, hooded = c.hooded }
end)

BSB.RegisterCallback('jobs:kid:carry', function(src, target)
    local t, c = myCaptive(src, target)
    if not t or not close(src, t, 3.0) then return { ok = false, error = Lp(src, 'err.not_there') } end
    c.carried = not c.carried
    pstate(t):set('bsCarriedBy', c.carried and src or nil, true)
    return { ok = true, carried = c.carried }
end)

BSB.RegisterCallback('jobs:kid:release', function(src, target)
    local t = myCaptive(src, target)
    if not t then return { ok = false, error = Lp(src, 'err.not_there') } end
    free(t, 'by captor')
    return { ok = true }
end)

BSB.RegisterCallback('jobs:kid:ransom', function(src, a)
    a = type(a) == 'table' and a or {}
    local t, c = myCaptive(src, a.target)
    if not t then return { ok = false, error = Lp(src, 'err.not_there') } end
    if not c.fid then return { ok = false, error = Lp(src, 'err.no_ransom_faction') } end
    local amount = math.floor(tonumber(a.amount) or 0)
    local cap = math.floor(tonumber(S.ransomCap) or 2500)
    if amount < 1 or amount > cap then return { ok = false, error = Lp(src, 'err.ransom_cap', { n = cap }) } end
    c.ransom = amount
    local name = J.Name(t)
    for _, v in ipairs(GetPlayers()) do
        local o = tonumber(v)
        if o ~= t and J.Faction(o) == c.fid then J.Notify(o, 'error', 'n.ransom_demand', { name = name, n = amount }) end
    end
    J.Notify(t, 'warn', 'n.ransom_on_you', { n = amount })
    J.Log(src, 'ransom', ('victim %d asks %d'):format(c.cid, amount))
    return { ok = true }
end)

BSB.RegisterCallback('jobs:kid:pay', function(src, a)
    a = type(a) == 'table' and a or {}
    local t = tonumber(a.target)
    local c = t and Captives[t]
    if not c or not c.ransom then return { ok = false, error = Lp(src, 'err.gone') } end
    if src == t or src == c.by or J.Faction(src) ~= c.fid then return { ok = false, error = Lp(src, 'err.no_perm') } end
    if not GetPlayerName(c.by) then free(t, 'captor gone'); return { ok = false, error = Lp(src, 'err.gone') } end
    local amount = c.ransom
    if a.from == 'treasury' then
        local ok, allowed = pcall(function() return exports.bs_factions:RankAllowed(src, 'withdraw') end)
        if not (ok and allowed) then return { ok = false, error = Lp(src, 'err.no_perm') } end
        local took = exports.bs_factions:TreasuryDebit(c.fid, amount, 'Ransom')
        if (tonumber(took) or 0) < amount then
            if (tonumber(took) or 0) > 0 then exports.bs_factions:TreasuryDeposit(c.fid, took, J.CharId(src), 'deposit', 'Ransom refund') end
            return { ok = false, error = Lp(src, 'err.no_money') }
        end
    else
        if not exports.bs_core:RemoveMoney(src, 'cash', amount, 'ransom') then return { ok = false, error = Lp(src, 'err.no_money') } end
    end
    exports.bs_core:AddMoney(c.by, 'cash', amount, 'ransom')
    J.Notify(c.by, 'success', 'n.ransom_paid', { n = amount })
    J.Progress(c.by, 'ransom_paid', 1)
    J.Log(src, 'ransom_paid', ('victim %d paid %d to %d (%s)'):format(c.cid, amount, c.byCid or 0, a.from == 'treasury' and 'treasury' or 'cash'))
    free(t, 'ransom paid')
    return { ok = true }
end)

-- Ransoms and captives shown in the JOBS tab.
J.OverviewExtra = function(src, cid, fid, out)
    local ransoms, mine = {}, {}
    for victim, c in pairs(Captives) do
        if c.fid == fid and c.ransom and victim ~= src then
            ransoms[#ransoms + 1] = { target = victim, name = J.Name(victim), amount = c.ransom, left = math.max(0, (S.kidnapMaxMinutes or 20) * 60 - (J.Now() - c.at)) }
        end
        if c.by == src then
            mine[#mine + 1] = { target = victim, name = J.Name(victim), ransom = c.ransom, hooded = c.hooded == true, carried = c.carried == true,
                                hasFaction = c.fid ~= nil, left = math.max(0, (S.kidnapMaxMinutes or 20) * 60 - (J.Now() - c.at)) }
        end
    end
    out.ransoms, out.captives = ransoms, mine
    out.canTreasury = false
    pcall(function() out.canTreasury = exports.bs_factions:RankAllowed(src, 'withdraw') == true end)
    local c = J.ActiveOf and J.ActiveOf(cid)
    out.active = c and c.id or nil
end

-- Auto release: timer, captor gone or far away, or the captive ends up in a safezone.
CreateThread(function()
    while true do
        Wait(5000)
        local limit = (tonumber(S.kidnapMaxMinutes) or 20) * 60
        for victim, c in pairs(Captives) do
            if not GetPlayerName(victim) then
                Captives[victim] = nil
            elseif not GetPlayerName(c.by) then
                free(victim, 'captor left')
            elseif J.Now() - c.at > limit then
                free(victim, 'timer')
            elseif not close(c.by, victim, 200.0) then
                free(victim, 'too far')
            else
                local p = J.PedPos(victim)
                if p and J.InSafeZone(p.x, p.y) then
                    c.safeTicks = (c.safeTicks or 0) + 1
                    if c.safeTicks >= 2 then free(victim, 'safezone') end
                else
                    c.safeTicks = 0
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    Captives[src] = nil
    for victim, c in pairs(Captives) do if c.by == src then free(victim, 'captor dropped') end end
end)

-- The captive's client asks to be released when it notices its captor is gone (state bag left over).
RegisterNetEvent('bs:jobs:checkCuffs', function()
    local src = source
    if not Captives[src] then
        local st = pstate(src)
        st:set('bsCuffed', nil, true); st:set('bsHooded', nil, true); st:set('bsCarriedBy', nil, true)
    end
end)

--------------------------------------------------------------------------------
-- Robbery at gunpoint (Raider): takes a share of the victim's bag.
--------------------------------------------------------------------------------

local SKIP = { weapon = true, clothing = true, currency = true, trophy = true, gear = true }
local UNARMED = joaat('WEAPON_UNARMED')

BSB.RegisterCallback('jobs:rob', function(src, target)
    if not J.Does(src, 'rob') then return { ok = false, error = Lp(src, 'err.wrong_job') } end
    if GetSelectedPedWeapon(GetPlayerPed(src)) == UNARMED then return { ok = false, error = Lp(src, 'err.need_gun') } end
    local t, err, cid = targetCheck(src, target, 'rob')
    if not t then return { ok = false, error = err } end
    local counts = INV:ItemCounts(t) or {}
    local pool, total = {}, 0
    for item, n in pairs(counts) do
        local def = INV:GetItem(item)
        if n > 0 and not (def and SKIP[def.category]) then pool[#pool + 1] = { item = item, n = n }; total = total + n end
    end
    if total == 0 then return { ok = false, error = Lp(src, 'err.bag_empty') } end
    local want = math.max(1, math.ceil(total * (tonumber(S.robPercent) or 20) / 100))
    local taken, units = {}, 0
    while units < want and #pool > 0 do
        local i = math.random(#pool)
        local e = pool[i]
        local n = math.min(e.n, want - units, math.random(1, math.max(1, e.n)))
        if INV:RemoveItem(t, e.item, n) then
            if INV:GiveItem(src, e.item, n) then
                taken[#taken + 1] = ('%dx %s'):format(n, e.item)
                units = units + n
            else
                INV:GiveItem(t, e.item, n)
                break
            end
        end
        e.n = e.n - n
        if e.n <= 0 then table.remove(pool, i) end
    end
    if units == 0 then return { ok = false, error = Lp(src, 'err.bag_full') } end
    J.MarkVictim(cid, 'rob')
    J.Notify(t, 'error', 'n.robbed', { n = units })
    J.Progress(src, 'player_robbed', 1)
    J.Log(src, 'rob', ('victim %d: %s'):format(cid, table.concat(taken, ', ')))
    return { ok = true, n = units }
end)

--------------------------------------------------------------------------------
-- Smugglers: while carrying contraband the courier's position leaks to the other factions.
--------------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(math.max(30, tonumber(S.smugglePingSeconds) or 120) * 1000)
        for _, c in pairs(J.Contracts or {}) do
            if c.status == 'taken' and c.tpl == 'sm_run' then
                local src = J.SrcOf(c.takenBy)
                local at = src and J.PedPos(src)
                if at and INV:CountItem(src, 'contraband') > 0 then
                    for _, v in ipairs(GetPlayers()) do
                        local o = tonumber(v)
                        if o ~= src and J.Faction(o) ~= c.fid then
                            TriggerClientEvent('bs:jobs:smugglePing', o, { x = at.x + math.random(-60, 60), y = at.y + math.random(-60, 60), z = at.z })
                        end
                    end
                end
            end
        end
    end
end)
