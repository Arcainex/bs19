-- bs_tutorial server. Owns progress (bs_tutorial_progress), the private routing bucket while it plays,
-- the faction pick, the starter kit and the first mission reward. The client only asks.

local S = Tutorial.Settings
local Rows = {}          -- [charId] = progress row
local Active = {}        -- [src] = { bucket = previous bucket, kind = 'tour' | 'pick' }
local Forced = {}        -- [src] = true while a staff force is pending (skips the combat check once)
function TutorialMarkForced(src) Forced[src] = true end
TutorialOverrides = { chapters = {} }

local function q(sql, p) return exports.oxmysql:query_async(sql, p or {}) or {} end
local function x(sql, p) return exports.oxmysql:update_async(sql, p or {}) end

local function notify(src, kind, msg)
    TriggerClientEvent('bs:ui:notify', src, { type = kind, message = msg, duration = 7000 })
end

-- One line per reward or staff action in the GUARD tab.
function TutorialLog(src, detail)
    local ped = GetPlayerPed(src)
    local c = (ped and ped ~= 0) and GetEntityCoords(ped) or vector3(0, 0, 0)
    local p = exports.bs_core:GetPlayer(src)
    exports.oxmysql:insert('INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,?,?,?,?,?)',
        { src, GetPlayerIdentifierByType(src, 'license'), p and p.charId or nil, (GetPlayerName(src) or '?'):sub(1, 64),
          'tutorial', 0, tostring(detail):sub(1, 512), c.x, c.y, c.z })
end

local function charOf(src)
    local p = exports.bs_core:GetPlayer(src)
    return p and p.charId or nil
end

-- oxmysql returns TINYINT(1) as true/false, other ints as numbers. tonumber(true) is nil, so every flag read false.
local function flag(v) return v == true or tonumber(v) == 1 end

local function decode(s, fallback)
    local ok, v = pcall(json.decode, s or '')
    return (ok and type(v) == 'table') and v or fallback
end

local SchemaReady = false
local function waitSchema()
    local t = 0
    while not SchemaReady and t < 30000 do Wait(100); t = t + 100 end
    return SchemaReady
end

local function load(cid)
    cid = tonumber(cid)
    if not cid then return nil end
    if Rows[cid] then return Rows[cid] end
    if not waitSchema() then return nil end
    local r = q('SELECT * FROM `bs_tutorial_progress` WHERE `character_id` = ? LIMIT 1', { cid })[1]
    if not r then return nil end
    Rows[cid] = {
        cid = cid, needsPick = flag(r.needs_pick), offered = flag(r.offered),
        chapters = decode(r.chapters, {}), completed = flag(r.completed), kitGiven = flag(r.kit_given),
        mission = (function(m) return (m and next(m)) and m or nil end)(decode(r.mission, nil)), missionDone = flag(r.mission_done),
        skipped = flag(r.skipped), missionClaimed = flag(r.mission_claimed),
    }
    -- Backfill: all steps done but never flagged complete (finished before the claim flow existed).
    local row, m = Rows[cid], Rows[cid].mission
    if m and not row.missionDone and m.loot and m.craft and (tonumber(m.kills) or 0) >= Tutorial.Mission.kills then
        row.missionDone = true
        x('UPDATE `bs_tutorial_progress` SET `mission_done` = 1 WHERE `character_id` = ?', { cid })
    end
    return Rows[cid]
end

-- Characters made before this resource have no row: they get one on demand, without the pick/offer.
local function ensure(cid)
    cid = tonumber(cid)
    local r = load(cid)
    if r or not cid or not SchemaReady then return r end
    x('INSERT IGNORE INTO `bs_tutorial_progress` (`character_id`, `needs_pick`, `offered`) VALUES (?, 0, 1)', { cid })
    Rows[cid] = nil
    return load(cid)
end

local function save(r)
    x([[UPDATE `bs_tutorial_progress` SET `needs_pick` = ?, `offered` = ?, `chapters` = ?, `completed` = ?, `kit_given` = ?,
        `mission` = ?, `mission_done` = ?, `skipped` = ?, `mission_claimed` = GREATEST(`mission_claimed`, ?) WHERE `character_id` = ?]],
        { r.needsPick and 1 or 0, r.offered and 1 or 0, json.encode(r.chapters), r.completed and 1 or 0, r.kitGiven and 1 or 0,
          json.encode(r.mission or {}), r.missionDone and 1 or 0,
          r.skipped and 1 or 0, r.missionClaimed and 1 or 0, r.cid })
end

-- Drops the cache so the next load reads the database (the claim flag is never trusted from memory).
local function fresh(cid)
    cid = tonumber(cid)
    if cid then Rows[cid] = nil end
    return cid and load(cid) or nil
end

-- Chapter ids that count for completion: built-in + custom, minus the ones staff disabled.
function TutorialChapterIds()
    local out = {}
    for _, list in ipairs({ Tutorial.Chapters, Tutorial.CustomChapters or {} }) do
        for _, c in ipairs(list) do
            local o = TutorialOverrides.chapters[c.id]
            if not (o and o.disabled) then out[#out + 1] = c.id end
        end
    end
    return out
end

local function chapterKnown(id)
    for _, c in ipairs(TutorialChapterIds()) do if c == id then return true end end
    return false
end

-- Buckets

local function enterBucket(src, kind)
    if Active[src] then Active[src].kind = kind return end
    Active[src] = { bucket = GetPlayerRoutingBucket(src), kind = kind }
    SetPlayerRoutingBucket(src, (S.bucketBase or 30000) + src)
    Player(src).state:set('bs_tutorial', kind, true)
end

local function leaveBucket(src)
    local a = Active[src]
    if not a then
        if GetPlayerName(src) and GetPlayerRoutingBucket(src) == (S.bucketBase or 30000) + src then
            SetPlayerRoutingBucket(src, 0)
            Player(src).state:set('bs_tutorial', false, true)
        end
        return
    end
    Active[src] = nil
    if GetPlayerName(src) then
        SetPlayerRoutingBucket(src, a.bucket or 0)
        Player(src).state:set('bs_tutorial', false, true)
    end
end

AddEventHandler('playerDropped', function() Active[source] = nil; Forced[source] = nil end)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(Active) do leaveBucket(src) end
end)

-- New characters get a row that asks for the pick and the offer.
AddEventHandler('bs:hook:character:created', function(_, charId)
    charId = tonumber(charId)
    if not charId then return end
    x('INSERT IGNORE INTO `bs_tutorial_progress` (`character_id`, `needs_pick`, `offered`) VALUES (?, ?, 0)',
        { charId, S.factionPicker and 1 or 0 })
end)

AddEventHandler('bs:hook:player:unloaded', function(player)
    local src = type(player) == 'table' and tonumber(player.source)
    if src then leaveBucket(src) end
end)

-- Faction picker

local function factionCard(id)
    for _, f in ipairs(Tutorial.Factions) do if f.id == id then return f end end
end

local function memberCounts()
    if GetResourceState('bs_factions') ~= 'started' then return {} end
    local ok, c = pcall(function() return exports.bs_factions:VanillaMemberCounts() end)
    return ok and type(c) == 'table' and c or {}
end

-- The smallest faction (ties: all of them) gets the bonus.
local function smallest(counts)
    local low
    for _, f in ipairs(Tutorial.Factions) do
        local n = counts[f.id] or 0
        if not low or n < low then low = n end
    end
    local out = {}
    for _, f in ipairs(Tutorial.Factions) do if (counts[f.id] or 0) == low then out[f.id] = true end end
    return out
end

local function pickData()
    local counts = memberCounts()
    local small = smallest(counts)
    local list = {}
    for _, f in ipairs(Tutorial.Factions) do
        list[#list + 1] = { id = f.id, colour = f.colour, members = counts[f.id] or 0, bonus = small[f.id] == true }
    end
    return { factions = list, bonusCash = S.smallestBonusCash, bonusXp = S.smallestBonusXp }
end

-- After spawning: does this character pick a faction, get the offer, or neither.
BSB.RegisterCallback('tutorial:spawnState', function(src)
    local cid = charOf(src)
    if not cid then return { ok = false } end
    local r = fresh(cid)
    if not r then return { ok = true } end
    local inFaction = GetResourceState('bs_factions') == 'started' and exports.bs_factions:GetFaction(src) or nil
    -- Faction chosen in the character creator: it is joined right after the first spawn, so no picker.
    local pl = exports.bs_core:GetPlayer(src)
    -- Characters with more than 10 minutes played never get the picker, the offer or a tutorial bucket.
    local row = q('SELECT `playtime` FROM `bs_characters` WHERE `id` = ? LIMIT 1', { cid })[1]
    local played = (row and tonumber(row.playtime) or 0) + (pl and math.max(0, os.time() - (tonumber(pl.lastSavedAt or pl.loadedAt) or os.time())) or 0)
    if played >= (S.veteranSeconds or 600) then
        if r.needsPick or not r.offered then r.needsPick = false; r.offered = true; save(r) end
        leaveBucket(src)
        return { ok = true }
    end
    local chosenAtCreation = pl and pl.metadata and type(pl.metadata.pendingFaction) == 'string'
    if r.needsPick and (inFaction or chosenAtCreation or not S.factionPicker or GetResourceState('bs_factions') ~= 'started') then
        r.needsPick = false; save(r)
    end
    if not r.needsPick and Active[src] and Active[src].kind == 'pick' then leaveBucket(src) end
    -- Offered once per character, ever: the flag is stored before the client shows it, so a crash, relog or
    -- closed NUI never brings it back.
    local offer = S.enabled and S.firstSpawnPrompt and not r.offered and not r.skipped and not r.completed and not r.mission and not r.missionClaimed and not r.needsPick
    if offer then r.offered = true; save(r); x('UPDATE `bs_tutorial_progress` SET `offered` = 1 WHERE `character_id` = ?', { r.cid }) end
    local out = { ok = true, offer = offer,
                  mission = r.mission and not r.missionClaimed and r.mission or nil, missionDone = r.missionDone,
                  missionClaimed = r.missionClaimed }
    if r.needsPick then
        out.pick = pickData()
        enterBucket(src, 'pick')
    end
    return out
end)

BSB.RegisterCallback('tutorial:pick', function(src, factionId)
    local cid = charOf(src)
    local r = cid and load(cid)
    if not r or not r.needsPick then return { ok = false, error = 'no pick pending' } end
    factionId = tostring(factionId or '')
    local card = factionCard(factionId)
    if not card then return { ok = false, error = 'unknown faction' } end

    local data = pickData()
    local res = exports.bs_factions:JoinVanilla(src, factionId)
    if type(res) ~= 'table' or not res.ok then return { ok = false, error = res and res.error or 'could not join' } end

    r.needsPick = false
    save(r)

    local bonus = false
    for _, f in ipairs(data.factions) do
        if f.id == factionId and f.bonus then bonus = true end
    end
    if bonus then
        if (S.smallestBonusCash or 0) > 0 then exports.bs_core:AddMoney(src, 'cash', S.smallestBonusCash, 'faction_pick_bonus') end
        if (S.smallestBonusXp or 0) > 0 then exports.bs_core:AddXP(src, S.smallestBonusXp, 'faction_pick_bonus') end
    end
    TutorialLog(src, ('picked faction %s%s'):format(factionId, bonus and ' (smallest-faction bonus)' or ''))

    -- First spawn goes to that faction's safezone.
    local sp = card.spawn
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then SetEntityCoords(ped, sp.x, sp.y, sp.z, false, false, false, false) end
    leaveBucket(src)
    local offer = S.enabled and S.firstSpawnPrompt and not r.offered and not r.skipped and not r.completed and not r.mission and not r.missionClaimed
    if offer then r.offered = true; save(r); x('UPDATE `bs_tutorial_progress` SET `offered` = 1 WHERE `character_id` = ?', { r.cid }) end
    return { ok = true, spawn = { x = sp.x, y = sp.y, z = sp.z, h = sp.w }, bonus = bonus, label = res.label, offer = offer }
end)

-- Character creator (bs_multichar)

local function GetFactionSafe(src)
    if GetResourceState('bs_factions') ~= 'started' then return nil end
    local ok, f = pcall(function() return exports.bs_factions:GetFaction(src) end)
    return ok and f or nil
end


-- Factions the creator may offer, with the safezone spawn of each. Empty when the picker is off or bs_factions is down, so the creator hides its step and the in-game picker stays the fallback.
exports('CreatorFactions', function()
    if not S.factionPicker or GetResourceState('bs_factions') ~= 'started' then return { factions = {} } end
    local data = pickData()
    for _, f in ipairs(data.factions) do
        local card = factionCard(f.id)
        if card then f.spawn = { x = card.spawn.x, y = card.spawn.y, z = card.spawn.z, h = card.spawn.w } end
    end
    return data
end)

-- Called by the creator right after the row exists: this character already has its faction, so the picker is skipped (needs_pick = 0).
exports('CreatorFactionChosen', function(charId)
    charId = tonumber(charId)
    if not charId or not waitSchema() then return false end
    x([[INSERT INTO `bs_tutorial_progress` (`character_id`, `needs_pick`, `offered`) VALUES (?, 0, 0)
        ON DUPLICATE KEY UPDATE `needs_pick` = 0]], { charId })
    Rows[charId] = nil
    return true
end)

-- First spawn of a character that chose its faction at creation: join it (the roster loads a moment after the spawn, so retry), grant the smallest-faction bonus once, then clear the marker.
AddEventHandler('bs:hook:player:spawned', function(player)
    local src = type(player) == 'table' and tonumber(player.source)
    local id = type(player) == 'table' and type(player.metadata) == 'table' and player.metadata.pendingFaction
    if not src or type(id) ~= 'string' then return end
    CreateThread(function()
        for _ = 1, 20 do
            if not GetPlayerName(src) then return end
            local card = factionCard(id)
            if not card or GetResourceState('bs_factions') ~= 'started' then break end
            local data = pickData()
            local res = exports.bs_factions:JoinVanilla(src, id)
            if type(res) == 'table' and (res.ok or GetFactionSafe(src)) then
                local bonus = false
                for _, f in ipairs(data.factions) do if f.id == id and f.bonus then bonus = true end end
                if res.ok and bonus then
                    if (S.smallestBonusCash or 0) > 0 then exports.bs_core:AddMoney(src, 'cash', S.smallestBonusCash, 'faction_pick_bonus') end
                    if (S.smallestBonusXp or 0) > 0 then exports.bs_core:AddXP(src, S.smallestBonusXp, 'faction_pick_bonus') end
                    TriggerClientEvent('bs:ui:notify', src, { type = 'info', duration = 8000,
                        message = Lp(src, 'pick.bonus_got', { cash = S.smallestBonusCash, xp = S.smallestBonusXp }) })
                end
                if res.ok then
                    TriggerClientEvent('bs:ui:notify', src, { type = 'success', duration = 8000, message = Lp(src, 'pick.joined', { name = res.label or '' }) })
                    TutorialLog(src, ('creator faction %s%s'):format(id, bonus and ' (smallest-faction bonus)' or ''))
                end
                break
            end
            Wait(1500)
        end
        pcall(function() exports.bs_core:SetPlayerMeta(src, 'pendingFaction', nil) end)
    end)
end)

-- The tour

BSB.RegisterCallback('tutorial:begin', function(src, forced)
    forced = forced and Forced[src] == true
    Forced[src] = nil
    if not S.enabled and not forced then return { ok = false, error = Lp(src, 'tut.disabled') } end
    local cid = charOf(src)
    if not cid then return { ok = false } end
    if Active[src] and Active[src].kind == 'pick' then return { ok = false } end
    if not forced and GetResourceState('bs_medical') == 'started' then
        local ok, downed = pcall(function() return exports.bs_medical:IsDowned(src) end)
        if ok and downed then return { ok = false, error = Lp(src, 'tut.combat') } end
    end
    local r = ensure(cid)
    if not r.offered then r.offered = true; save(r) end
    enterBucket(src, 'tour')
    return { ok = true, done = r.chapters, completed = r.completed, overrides = TutorialOverrides.chapters,
             missionAvailable = S.missionEnabled and not r.missionDone and not r.mission }
end)

BSB.RegisterCallback('tutorial:end', function(src)
    if not Active[src] or Active[src].kind == 'tour' then leaveBucket(src) end
    return { ok = true }
end)

RegisterNetEvent('bs:tutorial:leave', function()
    local src = source
    if Active[src] and Active[src].kind == 'tour' then
        leaveBucket(src)
    elseif not Active[src] and Player(src).state.bs_tutorial == 'tour' then
        leaveBucket(src)
    end
end)

BSB.RegisterCallback('tutorial:offer', function(src, accepted)
    local cid = charOf(src)
    local r = cid and load(cid)
    if r then
        r.offered = true
        if not accepted then r.skipped = true end
        save(r)
    end
    return { ok = true }
end)

local function giveList(src, list)
    for _, it in ipairs(list or {}) do
        pcall(function() exports.bs_inventory:GiveItem(src, it.item, it.amount) end)
    end
end

BSB.RegisterCallback('tutorial:chapterDone', function(src, id)
    if not Active[src] or Active[src].kind ~= 'tour' then return { ok = false } end
    id = tostring(id or '')
    if not chapterKnown(id) then return { ok = false } end
    local cid = charOf(src)
    local r = cid and ensure(cid)
    if not r then return { ok = false } end
    r.chapters[id] = true

    local all = true
    for _, c in ipairs(TutorialChapterIds()) do if not r.chapters[c] then all = false break end end
    local reward = false
    if all and not r.completed then
        r.completed = true
        if not r.kitGiven then
            r.kitGiven = true
            reward = true
            giveList(src, Tutorial.StarterKit)
            if (S.completionXp or 0) > 0 then exports.bs_core:AddXP(src, S.completionXp, 'tutorial_complete') end
            TutorialLog(src, 'completed the tutorial: starter kit + ' .. tostring(S.completionXp) .. ' XP')
        end
    end
    save(r)
    return { ok = true, done = r.chapters, completed = r.completed, reward = reward }
end)

-- First mission

local function pushMission(src, r)
    TriggerClientEvent('bs:tutorial:mission', src, r.mission, r.missionDone, r.missionClaimed)
end

BSB.RegisterCallback('tutorial:missionStart', function(src)
    if not S.missionEnabled then return { ok = false } end
    local cid = charOf(src)
    local r = cid and ensure(cid)
    if not r or r.missionDone then return { ok = false, error = Lp(src, 'mis.already') } end
    r.mission = r.mission or { loot = false, craft = false, kills = 0 }
    save(r)
    pushMission(src, r)
    return { ok = true, mission = r.mission }
end)

local function progress(src, what)
    local cid = charOf(src)
    local r = cid and load(cid)
    if not r or not r.mission or r.missionDone or r.missionClaimed then return end
    local m = r.mission
    if what == 'loot' then if m.loot then return end m.loot = true
    elseif what == 'craft' then if m.craft then return end m.craft = true
    elseif what == 'kill' then if m.kills >= Tutorial.Mission.kills then return end m.kills = m.kills + 1
    else return end

    if m.loot and m.craft and m.kills >= Tutorial.Mission.kills then
        -- Complete: the reward waits for "Finish mission" in the inventory Mission Log (claim below).
        r.missionDone = true
        notify(src, 'success', Lp(src, 'mis.ready'))
    end
    save(r)
    pushMission(src, r)
end

-- Server-side sources only: these events are not registered as net events.
local function fromServer() local s = source return s == nil or s == '' or tonumber(s) == nil or tonumber(s) <= 0 end

AddEventHandler('bs:tutorial:event', function(src, kind)
    if not fromServer() then return end
    if kind == 'loot' then progress(tonumber(src), 'loot') end
end)

AddEventHandler('bs:jobs:event', function(src, kind, _, meta)
    if not fromServer() then return end
    if (kind == 'craft' or kind == 'craft_food') and type(meta) == 'table' and meta.item == Tutorial.Mission.craftItem then
        progress(tonumber(src), 'craft')
    end
end)

AddEventHandler('bs:hook:player:action', function(player, actionId)
    local src = type(player) == 'table' and tonumber(player.source)
    if not src or type(actionId) ~= 'string' or not actionId:find('^zombie_kill') then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local c = GetEntityCoords(ped)
    if GetResourceState('bs_zombies') == 'started' then
        local ok, inside = pcall(function() return exports.bs_zombies:InSafeZone(c.x, c.y, 0.0) end)
        if ok and inside then return end
    end
    progress(src, 'kill')
end)

-- Staff: F10 force
exports('ForceTutorial', function(target)
    target = tonumber(target)
    if not target or not GetPlayerName(target) or not charOf(target) then return false end
    Forced[target] = true
    TriggerClientEvent('bs:tutorial:force', target)
    TutorialLog(target, 'tutorial forced by staff')
    return true
end)

-- Table, created here too so a fresh server works before the migration runs.
CreateThread(function()
    pcall(function() exports.oxmysql:awaitConnection() end)
    x([[CREATE TABLE IF NOT EXISTS `bs_tutorial_progress` (
        `character_id` INT UNSIGNED NOT NULL,
        `needs_pick`   TINYINT(1) NOT NULL DEFAULT 0,
        `offered`      TINYINT(1) NOT NULL DEFAULT 0,
        `chapters`     TEXT NULL,
        `completed`    TINYINT(1) NOT NULL DEFAULT 0,
        `kit_given`    TINYINT(1) NOT NULL DEFAULT 0,
        `mission`      TEXT NULL,
        `mission_done` TINYINT(1) NOT NULL DEFAULT 0,
        `skipped`      TINYINT(1) NOT NULL DEFAULT 0,
        `mission_claimed` TINYINT(1) NOT NULL DEFAULT 0,
        PRIMARY KEY (`character_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    -- Columns from 039_tutorial_flags.sql, added here too for servers that skipped the migration.
    for col, def in pairs({ skipped = 'TINYINT(1) NOT NULL DEFAULT 0', mission_claimed = 'TINYINT(1) NOT NULL DEFAULT 0' }) do
        -- SHOW COLUMNS, not information_schema: some MySQL users cannot read information_schema, which made this
        -- think the column existed. Without mission_claimed every claim UPDATE failed and nothing was ever saved.
        local has = q(('SHOW COLUMNS FROM `bs_tutorial_progress` LIKE \'%s\''):format(col))[1]
        if not has then
            x(('ALTER TABLE `bs_tutorial_progress` ADD COLUMN `%s` %s'):format(col, def))
            if col == 'mission_claimed' then x('UPDATE `bs_tutorial_progress` SET `mission_claimed` = `mission_done`') end
            has = q(('SHOW COLUMNS FROM `bs_tutorial_progress` LIKE \'%s\''):format(col))[1]
            print(('^3[bs_tutorial]^7 added missing column %s: %s'):format(col, has and 'ok' or 'FAILED'))
        end
    end
    Rows = {}
    SchemaReady = true
end)

-- Mission Log (bs_inventory). Generic provider contract: MissionLogList(src) -> entries, MissionLogClaim(src, id) -> { ok }.
exports('MissionLogList', function(src)
    local cid = charOf(src)
    local r = cid and fresh(cid)
    if not r or not r.mission then return {} end
    local m = r.mission
    local all = m.loot == true and m.craft == true and (m.kills or 0) >= Tutorial.Mission.kills
    if all and not r.missionDone then r.missionDone = true; save(r) end
    local reward = {}
    for _, it in ipairs(Tutorial.Mission.reward) do reward[#reward + 1] = { item = it.item, amount = it.amount } end
    return { {
        id = 'tutorial_first', title = Lp(src, 'mis.title'), complete = r.missionDone, claimed = r.missionClaimed, reward = reward,
        steps = {
            { label = Lp(src, 'mis.loot'), done = m.loot == true },
            { label = Lp(src, 'mis.craft'), done = m.craft == true },
            { label = Lp(src, 'mis.kill', { n = math.min(m.kills or 0, Tutorial.Mission.kills), need = Tutorial.Mission.kills }),
              done = (m.kills or 0) >= Tutorial.Mission.kills },
        },
    } }
end)

local Claiming = {}   -- [cid] = true while a claim runs
local StuckPress = {} -- [cid] = os.time() of the last failed claim

exports('MissionLogClaim', function(src, id)
    if id ~= 'tutorial_first' then return { ok = false } end
    local cid = tonumber(charOf(src))
    if not cid or Claiming[cid] then return { ok = false } end
    Claiming[cid] = true
    local okRun, out = pcall(function()
        -- Row first (a missing row would make every UPDATE hit 0 rows), then the cache is dropped and read back.
        if not SchemaReady then return { ok = false } end
        x('INSERT IGNORE INTO `bs_tutorial_progress` (`character_id`, `needs_pick`, `offered`) VALUES (?, 0, 1)', { cid })
        local r = fresh(cid)
        if not r or not r.mission then return { ok = false } end
        if r.missionClaimed then return { ok = false, error = Lp(src, 'mis.already') } end
        if not r.missionDone then return { ok = false, error = Lp(src, 'mis.not_done') } end
        -- Claimed flag is written on its own first and read back; the affected-rows count is not trusted
        -- (it is not a plain number on every oxmysql build, which made a good write look like "already claimed").
        -- The flag was read as 0 just above and Claiming[cid] blocks a second claim in flight, so no AND-guard here.
        local res = x('UPDATE `bs_tutorial_progress` SET `mission_claimed` = 1, `mission_done` = 1 WHERE `character_id` = ?', { cid })
        local chk = q('SELECT * FROM `bs_tutorial_progress` WHERE `character_id` = ? LIMIT 1', { cid })[1]
        if not chk or not flag(chk.mission_claimed) then
            local ddl = q('SHOW CREATE TABLE `bs_tutorial_progress`')[1]
            print(('^1[bs_tutorial]^7 claim not saved for char %d (update result: %s)\nrow: %s\ntable: %s'):format(
                cid, json.encode(res), json.encode(chk), json.encode(ddl)))
            return { ok = false }
        end
        r.missionClaimed = true
        save(r)
        giveList(src, Tutorial.Mission.reward)
        notify(src, 'success', Lp(src, 'mis.done'))
        TutorialLog(src, 'claimed the first mission reward: pistol kit')
        pushMission(src, r)
        return { ok = true }
    end)
    Claiming[cid] = nil
    if not okRun then print('^1[bs_tutorial]^7 claim error: ' .. tostring(out)) out = { ok = false } end
    -- Safety net: a second failed press within a minute force-finishes the mission (same as /finishtutorial),
    -- so a player can never be stuck with a tracker that will not go away.
    if not (out and out.ok) then
        local now = os.time()
        if StuckPress[cid] and now - StuckPress[cid] <= 60 then
            StuckPress[cid] = nil
            x([[UPDATE `bs_tutorial_progress` SET `mission_done` = 1, `mission_claimed` = 1 WHERE `character_id` = ?]], { cid })
            Rows[cid] = nil
            TriggerClientEvent('bs:tutorial:mission', src, {}, true, true)
            TutorialLog(src, ('first mission force-finished after repeated failed claims (char %d)'):format(cid))
            out = { ok = true }
        else
            StuckPress[cid] = now
        end
    else
        StuckPress[cid] = nil
    end
    return out
end)

local function registerLog()
    if GetResourceState('bs_inventory') == 'started' then
        pcall(function() exports.bs_inventory:RegisterMissionSource(GetCurrentResourceName()) end)
    end
end
CreateThread(function() Wait(1000); registerLog() end)
AddEventHandler('onResourceStart', function(res) if res == 'bs_inventory' then SetTimeout(1000, registerLog) end end)

AddEventHandler('bs:hook:player:loaded', function(player)
    local cid = type(player) == 'table' and tonumber(player.charId)
    local src = type(player) == 'table' and tonumber(player.source)
    if not cid then return end
    Rows[cid] = nil
    -- A character that still has to pick a faction is hidden from the first frame; the pick then decides the spawn.
    CreateThread(function()
        local r = load(cid)
        if r and r.needsPick and S.factionPicker and src and GetPlayerName(src) and not Active[src] then enterBucket(src, 'pick') end
    end)
end)

-- Admin debug: prints the server's view of your tutorial row.
RegisterCommand('tutorialstate', function(src)
    local ok = src == 0
    if not ok and GetResourceState('bs_admin') == 'started' then
        local a, yes = pcall(function() return exports.bs_admin:IsAdmin(src) end)
        ok = a and yes == true
    end
    if not ok then return end
    local cid = src ~= 0 and charOf(src) or nil
    local r = cid and fresh(cid)
    local line = r and ('char %s needsPick=%s offered=%s done=%s claimed=%s mission=%s schema=%s'):format(cid, tostring(r.needsPick),
        tostring(r.offered), tostring(r.missionDone), tostring(r.missionClaimed), json.encode(r.mission or {}), tostring(SchemaReady))
        or ('no row (char %s, schema=%s)'):format(tostring(cid), tostring(SchemaReady))
    print('[bs_tutorial] ' .. line)
    if src ~= 0 then TriggerClientEvent('chat:addMessage', src, { args = { 'bs_tutorial', line } }) end
end, false)


-- Staff tools. finishtutorial [serverId]: marks the first mission done and claimed, no reward, tracker gone.
-- tutorialwipeall confirm: copies the table to bs_tutorial_progress_bak_<time>, then clears every row so all characters start fresh.
local function staffOnly(src)
    if src == 0 then return true end
    if GetResourceState('bs_admin') ~= 'started' then return false end
    local a, yes = pcall(function() return exports.bs_admin:IsAdmin(src) end)
    return a and yes == true
end

RegisterCommand('finishtutorial', function(src, args)
    if not staffOnly(src) then return end
    local target = tonumber(args[1]) or src
    if target == 0 then print('usage: finishtutorial <serverId>') return end
    local cid = tonumber(charOf(target))
    if not cid then print('[bs_tutorial] no character for ' .. tostring(target)) return end
    x('INSERT IGNORE INTO `bs_tutorial_progress` (`character_id`, `needs_pick`, `offered`) VALUES (?, 0, 1)', { cid })
    x([[UPDATE `bs_tutorial_progress` SET `needs_pick` = 0, `offered` = 1, `completed` = 1, `skipped` = 1,
        `mission_done` = 1, `mission_claimed` = 1 WHERE `character_id` = ?]], { cid })
    local r = fresh(cid)
    print(('[bs_tutorial] finishtutorial char %d -> claimed=%s'):format(cid, tostring(r and r.missionClaimed)))
    if r then pushMission(target, r) end
    TriggerClientEvent('bs:tutorial:mission', target, {}, true, true)
    TutorialLog(src ~= 0 and src or target, ('finishtutorial on char %d'):format(cid))
end, false)

RegisterCommand('tutorialwipeall', function(src, args)
    if not staffOnly(src) then return end
    if args[1] ~= 'confirm' then
        local msg = BSLocale.T(src == 0 and 'en' or BSLocale.LangOf(src), 'tut.wipe_confirm')
        if src == 0 then print(msg) else TriggerClientEvent('chat:addMessage', src, { args = { 'bs_tutorial', msg } }) end
        return
    end
    local bak = 'bs_tutorial_progress_bak_' .. os.time()
    x(('CREATE TABLE `%s` AS SELECT * FROM `bs_tutorial_progress`'):format(bak))
    x('DELETE FROM `bs_tutorial_progress`')
    Rows = {}
    print(('[bs_tutorial] tutorial progress wiped for all characters (backup table %s)'):format(bak))
    for _, id in ipairs(GetPlayers()) do TriggerClientEvent('bs:tutorial:mission', tonumber(id), {}, true, true) end
    TutorialLog(src ~= 0 and src or 0, 'wiped all tutorial progress, backup ' .. bak)
end, false)
