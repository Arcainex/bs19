-- Dark Zone level: own XP, ranks with titles and rewards. One row per character in bs_dz_progress.

Prog = { rows = {} }   -- [charId] = { xp, rank, extracts, kills, deaths, owed = {} }

local S = function() return DZ.Settings end
local zkill = {}       -- [src] = { t = minute, xp = given this minute }

local function load(cid)
    if Prog.rows[cid] then return Prog.rows[cid] end
    local r = exports.oxmysql:single_async('SELECT * FROM `bs_dz_progress` WHERE `character_id` = ?', { cid })
    local row = { xp = 0, rank = 1, extracts = 0, kills = 0, deaths = 0, owed = {} }
    if r then
        row.xp, row.rank = tonumber(r.xp) or 0, tonumber(r.rank) or 1
        row.extracts, row.kills, row.deaths = tonumber(r.extracts) or 0, tonumber(r.kills) or 0, tonumber(r.deaths) or 0
        local ok, o = pcall(json.decode, r.owed or '[]')
        row.owed = ok and type(o) == 'table' and o or {}
    end
    Prog.rows[cid] = row
    return row
end

local function save(cid, row)
    exports.oxmysql:execute([[INSERT INTO `bs_dz_progress` (`character_id`,`xp`,`rank`,`extracts`,`kills`,`deaths`,`owed`) VALUES (?,?,?,?,?,?,?)
        ON DUPLICATE KEY UPDATE `xp`=VALUES(`xp`),`rank`=VALUES(`rank`),`extracts`=VALUES(`extracts`),`kills`=VALUES(`kills`),`deaths`=VALUES(`deaths`),`owed`=VALUES(`owed`)]],
        { cid, row.xp, row.rank, row.extracts, row.kills, row.deaths, json.encode(row.owed or {}) })
end

local function rowOf(src)
    local cid = DZU.charId(src)
    if not cid then return nil end
    return load(cid), cid
end

function Prog.View(src)
    local row = rowOf(src)
    if not row then return nil end
    local idx, cur, nxt = DZ.RankFor(row.xp)
    return { xp = row.xp, rank = idx, key = cur.key, title = Lp(src, 'dz.rank.' .. cur.key),
             nextXp = nxt and nxt.xp or nil, baseXp = cur.xp, extracts = row.extracts, kills = row.kills, deaths = row.deaths }
end

function Prog.Push(src)
    local v = Prog.View(src)
    if not v then return end
    Player(src).state:set('bsDzRank', v.key, true)
    TriggerClientEvent('bs:dz:prog', src, v)
end

-- Gives what is owed (rank rewards that did not fit). Keeps what still does not fit.
function Prog.Deliver(src)
    local row, cid = rowOf(src)
    if not row or #row.owed == 0 then return end
    local keep = {}
    for _, it in ipairs(row.owed) do
        local ok, given = pcall(function() return exports.bs_inventory:GiveItem(src, it.item, it.amount or 1) end)
        if not (ok and given) then keep[#keep + 1] = it end
    end
    if #keep ~= #row.owed then
        DZU.notify(src, 'success', 'dz.owed_given')
    end
    row.owed = keep
    save(cid, row)
end

function Prog.Add(src, xp, reason)
    xp = math.floor((tonumber(xp) or 0) * math.max(0, tonumber(S().xpMult) or 1.0) + 0.5)
    if xp <= 0 then return 0 end
    local row, cid = rowOf(src)
    if not row then return 0 end
    local before = DZ.RankFor(row.xp)
    row.xp = row.xp + xp
    local after = DZ.RankFor(row.xp)
    if after > row.rank then
        for i = math.max(row.rank, before) + 1, after do
            local r = DZ.Ranks[i]
            for _, it in ipairs(r and r.reward or {}) do
                if DZU.itemExists(it.item) then row.owed[#row.owed + 1] = { item = it.item, amount = it.amount or 1 } end
            end
            DZU.notify(src, 'success', 'dz.rank_up', { rank = Lp(src, 'dz.rank.' .. r.key) }, 8000)
        end
        row.rank = after
    end
    save(cid, row)
    if #row.owed > 0 then Prog.Deliver(src) end
    TriggerClientEvent('bs:dz:xp', src, xp)
    Prog.Push(src)
    return xp
end

function Prog.Count(src, field)
    local row, cid = rowOf(src)
    if not row or row[field] == nil then return end
    row[field] = row[field] + 1
    save(cid, row)
end

-- Zombie kills inside (hook from bs_zombies). Ordinary kills are capped per minute.
AddEventHandler('bs:zombies:killed', function(src, tag, typeId, x, y)
    src = tonumber(src)
    if not src or not DZU.on() or not Zone.inside[src] then return end
    local elite = tag == 'dz_elite'
    local xp = elite and (tonumber(S().xpEliteKill) or 40) or (tonumber(S().xpZombieKill) or 4)
    if not elite then
        local m = math.floor(os.time() / 60)
        local z = zkill[src]
        if not z or z.t ~= m then z = { t = m, xp = 0 }; zkill[src] = z end
        if z.xp >= 60 then return end
        z.xp = z.xp + xp
    end
    Prog.Add(src, xp, elite and 'elite' or 'zombie')
end)

AddEventHandler('bs:hook:player:loaded', function(player)
    local src = player and tonumber(player.source)
    if not src then return end
    SetTimeout(4000, function()
        if not GetPlayerName(src) then return end
        Prog.Push(src)
        Prog.Deliver(src)
    end)
end)

AddEventHandler('bs:hook:player:unloaded', function(player)
    if player and player.charId then Prog.rows[player.charId] = nil end
end)

AddEventHandler('playerDropped', function() zkill[source] = nil end)

BSB.RegisterCallback('dz:prog', function(src) return Prog.View(src) end)

exports('GetProgress', function(src) return Prog.View(tonumber(src)) end)
exports('AddXP', function(src, xp, reason) return Prog.Add(tonumber(src), xp, reason) end)
