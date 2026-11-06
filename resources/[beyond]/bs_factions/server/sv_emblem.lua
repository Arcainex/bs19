-- bs_factions - emblems (stored as a validated spec on the registry row) and the safezone banners that fly them.

local C = FactionsCore
local Banners, BannersLoaded = {}, false
local lastEdit = {}

local function fail(src, key) return { ok = false, error = Lp(src, key) } end

local function decode(raw)
    if type(raw) ~= 'string' or raw == '' then return nil end
    return (Emblem.Validate(raw))
end

-- Stored emblem, then the vanilla one from config, else nil (the NUI falls back to the old logo or a stable default).
function FactionEmblem(fid)
    local f = fid and C.Registry[fid]
    if f and f.emblem then return f.emblem end
    local def = Factions.List[fid or '']
    if def and def.emblem then return (Emblem.Validate(def.emblem)) end
    return nil
end

-- Identity block for the vanilla factions. Text keys are resolved in the menu's locale files.
function FactionIdentity(fid)
    local def = Factions.List[fid or '']
    if not def then return nil end
    local ranks = {}
    for _, r in ipairs((Factions.DefaultRanks or {})[fid] or {}) do ranks[r.id] = r.label end
    local c = def.colour or {}
    return { id = fid, motto = def.motto, lore = def.lore, colour = ('#%02x%02x%02x'):format(c.r or 200, c.g or 140, c.b or 70), ranks = ranks }
end

local function canEdit(src)
    local s = C.state(src)
    if not s or not s.id then return false, s end
    return s.rank == 'owner' or C.rankHas(s.id, s.rank, 'emblem_edit'), s
end

local function store(fid, spec)
    local f = C.Registry[fid]
    if not f then return false end
    C.x('UPDATE bs_faction_registry SET emblem=? WHERE faction_id=?', { spec and Emblem.Encode(spec) or nil, fid })
    f.emblem = spec
    local shown = FactionEmblem(fid)
    TriggerClientEvent('bs:factions:emblem', -1, fid, shown, f.logo)
    for s, st in pairs(C.State) do if st.id == fid then C.sync(s) end end
    return true, shown
end

local function readArgs(a)
    a = type(a) == 'table' and a or {}
    if a.reset == true then return true, nil end
    local spec, why = Emblem.Validate(a.spec)
    return spec ~= nil, spec, why
end

BSB.RegisterCallback('factions:emblem:get', function(src)
    local ok, s = canEdit(src)
    if not s or not s.id then return fail(src, 'fac.you_are_not_in_a_faction') end
    local f = C.Registry[s.id]
    return { ok = true, emblem = FactionEmblem(s.id), custom = f and f.emblem ~= nil, logo = f and f.logo, canEdit = ok, isConfig = f and f.config or false }
end)

BSB.RegisterCallback('factions:emblem:set', function(src, a)
    if not C.ready() then return fail(src, 'fac.faction_service_is_starting') end
    local ok, s = canEdit(src)
    if not s or not s.id then return fail(src, 'fac.you_are_not_in_a_faction') end
    if not ok then return fail(src, 'fac.emblem_no_perm') end
    local now = os.time()
    if lastEdit[src] and now - lastEdit[src] < (Factions.EmblemCooldown or 5) then return fail(src, 'fac.emblem_wait') end
    local valid, spec = readArgs(a)
    if not valid then return fail(src, 'fac.that_emblem_is_invalid') end
    lastEdit[src] = now
    local done, shown = store(s.id, spec)
    if not done then return fail(src, 'fac.faction_data_is_missing') end
    print(('[bs_factions] emblem of %s changed by %s (#%s)'):format(s.id, GetPlayerName(src) or '?', src))
    return { ok = true, emblem = shown, custom = spec ~= nil }
end)

BSB.RegisterCallback('factions:admin:emblem', function(src, a)
    if not C.isAdmin(src) then return fail(src, 'fac.not_allowed') end
    a = type(a) == 'table' and a or {}
    local fid = tostring(a.id or '')
    if not C.Registry[fid] then return fail(src, 'fac.faction_not_found') end
    local valid, spec = readArgs(a)
    if not valid then return fail(src, 'fac.the_emblem_is_invalid') end
    local _, shown = store(fid, spec)
    print(('^3[BS FACTION ADMIN]^7 %s (#%s) -> emblem [%s] %s'):format(GetPlayerName(src) or '?', src, fid, spec and Emblem.Encode(spec) or 'reset'))
    return { ok = true, emblem = shown, custom = spec ~= nil }
end)

-- Emblems for a handful of factions (banners, name tags). Unknown ids are skipped.
BSB.RegisterCallback('factions:emblems', function(_, ids)
    local out, n = {}, 0
    for _, id in ipairs(type(ids) == 'table' and ids or {}) do
        id = tostring(id)
        local f = C.Registry[id]
        if f and not out[id] then
            out[id] = { emblem = FactionEmblem(id), logo = f.logo, label = f.label, short = f.short }
            n = n + 1
            if n >= 32 then break end
        end
    end
    return out
end)

exports('GetEmblem', function(fid) return FactionEmblem(fid) end)
exports('GetIdentity', function(fid) return FactionIdentity(fid) end)

-- Banners: database rows replace the config defaults for that faction.
local function bannerList()
    local out, fromDb = {}, {}
    for _, b in ipairs(Banners) do out[#out + 1] = b; fromDb[b.factionId] = true end
    for fid, list in pairs((Factions.Banners or {}).defaults or {}) do
        if not fromDb[fid] then
            for i, b in ipairs(list) do out[#out + 1] = { id = 'cfg_' .. fid .. '_' .. i, factionId = fid, x = b.pos.x, y = b.pos.y, z = b.pos.z, heading = b.heading or 0.0 } end
        end
    end
    return out
end

local function loadBanners()
    Banners = {}
    for _, r in ipairs(C.q('SELECT id,faction_id,x,y,z,heading FROM bs_faction_banners ORDER BY id')) do
        Banners[#Banners + 1] = { id = tonumber(r.id), factionId = r.faction_id, x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z), heading = tonumber(r.heading) or 0.0 }
    end
    BannersLoaded = true
end

local function pushBanners(target) TriggerClientEvent('bs:factions:banners', target or -1, bannerList()) end

BSB.RegisterCallback('factions:banners', function() return { ok = BannersLoaded, enabled = (Factions.Banners or {}).enabled ~= false, list = bannerList() } end)

-- /factionbanner add <faction>  |  remove  |  list   (staff)
RegisterCommand('factionbanner', function(src, args)
    if src == 0 or not C.isAdmin(src) then return end
    local say = function(msg) TriggerClientEvent('bs:ui:notify', src, { type = 'info', message = msg, duration = 6000 }) end
    local sub = tostring(args[1] or 'list'):lower()
    local ped = GetPlayerPed(src)
    local at = ped ~= 0 and GetEntityCoords(ped) or vector3(0, 0, 0)
    if sub == 'add' then
        local fid = tostring(args[2] or ''):lower()
        if not C.Registry[fid] then return say(Lp(src, 'fac.faction_not_found')) end
        local h = ped ~= 0 and GetEntityHeading(ped) or 0.0
        C.x('INSERT INTO bs_faction_banners(faction_id,x,y,z,heading,created_by) VALUES(?,?,?,?,?,?)', { fid, at.x, at.y, at.z - 1.0, h, tonumber((C.state(src) or {}).cid) })
        loadBanners(); pushBanners()
        say(Lp(src, 'fac.banner_added', { faction = C.Registry[fid].label }))
    elseif sub == 'remove' then
        local best, bd = nil, 6.0
        for _, b in ipairs(Banners) do local d = #(at - vector3(b.x, b.y, b.z)); if d < bd then best, bd = b, d end end
        if not best then return say(Lp(src, 'fac.banner_none_near')) end
        C.x('DELETE FROM bs_faction_banners WHERE id=?', { best.id })
        loadBanners(); pushBanners()
        say(Lp(src, 'fac.banner_removed'))
    else
        local n = {}
        for _, b in ipairs(bannerList()) do n[b.factionId] = (n[b.factionId] or 0) + 1 end
        local parts = {}
        for fid, c in pairs(n) do parts[#parts + 1] = fid .. ' ' .. c end
        say(Lp(src, 'fac.banner_list', { list = #parts > 0 and table.concat(parts, ', ') or '-' }))
    end
end, false)

AddEventHandler('playerDropped', function() lastEdit[source] = nil end)

CreateThread(function()
    while not C.ready() do Wait(250) end
    -- Same columns as migration 047, for servers that run with migrations off.
    pcall(C.x, 'ALTER TABLE bs_faction_registry ADD COLUMN IF NOT EXISTS emblem TEXT NULL')
    pcall(C.x, 'CREATE TABLE IF NOT EXISTS bs_faction_banners (id INT UNSIGNED NOT NULL AUTO_INCREMENT, faction_id VARCHAR(32) NOT NULL, x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL, heading FLOAT NOT NULL DEFAULT 0, created_by INT UNSIGNED NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (id), KEY ix_bs_faction_banners_faction (faction_id))')
    for _, row in ipairs(C.q('SELECT faction_id, emblem FROM bs_faction_registry WHERE emblem IS NOT NULL')) do
        local f = C.Registry[row.faction_id]
        if f then f.emblem = decode(row.emblem) end
    end
    loadBanners()
    pushBanners()
end)

-- Public badge artwork used by the weapon sticker collection.
exports('GetStickerEmblems',function()
    local ids={};for id in pairs(C.Registry)do ids[#ids+1]=id end;table.sort(ids)
    local out={}
    for i=1,math.min(32,#ids)do local id=ids[i];local f=C.Registry[id]
        out[#out+1]={id=id,label=f.label or id,emblem=FactionEmblem(id),logo=f.logo}
    end
    return out
end)
