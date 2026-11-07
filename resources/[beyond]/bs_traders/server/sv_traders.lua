-- bs_traders - server side. All transactions and mission decisions are made here; the client only asks and nothing it says about prices, stock or kills is trusted.
-- NPC and mission definitions come from Registry (sv_registry.lua) so /traderdebug edits apply live.

-- Admin check shared by every editor callback below. Editing is admin only (teleportAces / bs_admin).
-- Ace list is in Traders.Settings.teleportAces (config_traders.lua).
local function isAdmin(src)
    for _, ace in ipairs(Traders.Settings.teleportAces or {}) do
        if IsPlayerAceAllowed(src, ace) then return true end
    end
    if GetResourceState('bs_admin') == 'started' then
        local ok, answer = pcall(function() return exports.bs_admin:IsAdmin(src) end)
        if ok and answer then return true end
    end
    return false
end

BSB.RegisterCallback('traders:debug:mayuse', function(src) return isAdmin(src) end)

-- Audit line in bs_guard_log (kind admin), same shape as bs_admin writes.
local function guardLog(src, detail)
    local ped = GetPlayerPed(src)
    local c = (ped and ped ~= 0) and GetEntityCoords(ped) or vector3(0, 0, 0)
    local okp, player = pcall(function() return exports.bs_core:GetPlayer(src) end)
    exports.oxmysql:insert(
        'INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,?,?,?,?,?)',
        { src, GetPlayerIdentifierByType(src, 'license'), okp and player and player.charId or nil,
          (GetPlayerName(src) or '?'):sub(1, 64), 'admin', 0, tostring(detail):sub(1, 512), c.x, c.y, c.z })
end

-- Per-player transaction lock

-- Per-source lock held for the whole callback. Callbacks check balance/stock, then yield (DB write, inventory call), so two rapid calls (double-click, spam) could both pass the same checks.
-- A second call while one is in flight returns 'busy'. pcall around the body guarantees the lock is released on error.
local txLock = {}

local function withTxLock(src, fn)
    if txLock[src] then return { ok = false, reason = 'busy' } end
    txLock[src] = true

    local ok, result = pcall(fn)

    txLock[src] = nil

    if not ok then
        print(('^1[bs_traders]^7 transaction callback error for src %s: %s')
            :format(tostring(src), tostring(result)))
        return { ok = false, reason = 'error' }
    end
    return result
end

-- Per-session mission state

-- [src] = { charId = n, missions = { [missionId] = { progress = n, npcId = s } } }
-- Kept in memory and written through on change, since progress increments on every zombie kill and cannot each be a query.
local State = {}

local function charIdOf(src)
    local entry = State[src]
    return entry and entry.charId
end

local function load(src, charId)
    local rows = exports.oxmysql:query_async(
        'SELECT `mission_id`, `npc_id`, `progress` FROM `bs_npc_missions` WHERE `character_id` = ?',
        { charId }) or {}

    local missions = {}
    for _, row in ipairs(rows) do
        missions[row.mission_id] = { progress = row.progress, npcId = row.npc_id }
    end

    State[src] = { charId = charId, missions = missions }
end

-- Lookups

local function npcHasRole(npc, role)
    return npc and (npc.role == role or npc.role == 'both')
end

local function sellEntry(npc, item)
    for _, e in ipairs(npc.sells or {}) do
        if e.item == item then return e end
    end
end

local function buyEntry(npc, item)
    for _, e in ipairs(npc.buys or {}) do
        if e.item == item then return e end
    end
end

-- Money goes through bs_core's plain-data exports, never methods on exports.bs_core:GetPlayer(): the export returns a serialised copy, so metatables and functions are gone (player:GetMoney is nil and throws).
-- A throw inside a bridge callback reaches the client as nil, which shows up as a timeout. There is no GetMoney export, so reads use GetPlayerSummary (accounts.cash).
local function cashOf(src)
    local ok, summary = pcall(function() return exports.bs_core:GetPlayerSummary(src) end)
    if not ok or type(summary) ~= 'table' then return 0 end
    return (summary.accounts and summary.accounts.cash) or 0
end

-- Faction skills trader_disc/trader_disc2/quartermaster: % off what the player pays.
local function discountPct(src)
    if GetResourceState('bs_factions') ~= 'started' then return 0 end
    local ok, n = pcall(function()
        local s = exports.bs_factions:GetFactionSummary(tonumber(src))
        if type(s) ~= 'table' or not s.factionId then return 0 end
        local t = 0
        for _, id in ipairs({ 'trader_disc', 'trader_disc2', 'quartermaster' }) do
            t = t + (tonumber(exports.bs_factions:GetSkillValue(s.factionId, id)) or 0)
        end
        return t
    end)
    return ok and math.max(0, math.min(50, tonumber(n) or 0)) or 0
end

local function discounted(price, pct)
    if pct <= 0 then return price end
    local m = BSConfigGet and tonumber(BSConfigGet('Global.traderPriceMultiplier', 1.0)) or 1.0  -- bs_config
    return math.max(1, math.floor(price * m * (100 - pct) / 100 + 0.5))
end

-- Faction access

-- Caller's vanilla faction id and rank index (1 = Leader), or nil.
local function factionOf(src)
    if GetResourceState('bs_factions') ~= 'started' then return nil, nil end
    local ok, sum = pcall(function() return exports.bs_factions:GetFactionSummary(tonumber(src)) end)
    if not ok or type(sum) ~= 'table' or not sum.factionId then return nil, nil end
    local idx
    local okr, r = pcall(function() return exports.bs_factions:RankIndex(sum.factionId, sum.rank) end)
    if okr then idx = tonumber(r) end
    return sum.factionId, idx
end

local function factionLabelKey(id) return 'ui.fac_' .. tostring(id) end

-- In-game hour from bs_world; nil when unknown (then the trader counts as open).
local function gameHour()
    if GetResourceState('bs_world') ~= 'started' then return nil end
    local ok, w = pcall(function() return exports.bs_world:WorldState() end)
    if ok and type(w) == 'table' and w.hour then return tonumber(w.hour) end
    return nil
end

local function isOpenNow(npc)
    local f, t = npc.openFrom or -1, npc.openTo or -1
    if f < 0 or t < 0 or f == t then return true end
    local h = gameHour()
    if not h then return true end
    if f < t then return h >= f and h < t end
    return h >= f or h < t   -- overnight range
end

-- nil when `src` may deal with this trader, else a locale key and vars (server enforced).
local function denyReason(src, npc, trade)
    -- Faction-only traders still sell to outsiders (at a surcharge); only non-trade use is refused.
    if not trade and npc.faction and npc.faction ~= '' then
        local fid = factionOf(src)
        if fid ~= npc.faction then
            return 'trd.e_faction', { faction = Lp(src, factionLabelKey(npc.faction)) }
        end
    end
    if not isOpenNow(npc) then
        return 'trd.e_closed', { from = npc.openFrom, to = npc.openTo }
    end
    return nil
end

-- A row's min faction rank: true if `src` meets it (0 or nil = anyone).
local function rankOk(src, npc, entry)
    local need = tonumber(entry and entry.minRank) or 0
    if need <= 0 then return true end
    local fid, idx = factionOf(src)
    if not fid or not idx then return false end
    if npc.faction and npc.faction ~= '' and fid ~= npc.faction then return false end
    return idx <= need
end

-- True when `src` is not in the faction a faction-only trader belongs to.
local function isOutsider(src, npc)
    if not (npc.faction and npc.faction ~= '') then return false end
    local fid = factionOf(src)
    return fid ~= npc.faction
end

-- Rank discount: pct per rank step above the lowest rank (lowest = 0%). Rank count comes from bs_factions.
local function rankDiscountPct(src, npc)
    local per = tonumber(Traders.Settings.rankDiscountPct) or 5
    if per <= 0 then return 0 end
    local fid, idx = factionOf(src)
    if not fid or not idx then return 0 end
    if npc.faction and npc.faction ~= '' and fid ~= npc.faction then return 0 end
    local okc, count = pcall(function() return exports.bs_factions:RankCount(fid) end)
    count = okc and tonumber(count) or nil
    if not count or count < 1 then return 0 end
    return math.max(0, math.min(50, per * math.max(0, count - idx)))
end

-- Price paid by the player: trader multiplier, then skill and rank discounts. Outsiders at a faction trader pay the surcharge, no discounts.
local function unitPrice(src, npc, base)
    local mult = tonumber(npc.priceMult) or 1.0
    local price = math.max(1, math.floor(base * mult + 0.5))
    if isOutsider(src, npc) then
        local sur = tonumber(Traders.Settings.outsiderSurchargePct) or 25
        return math.max(1, math.floor(price * (100 + sur) / 100 + 0.5))
    end
    local pct = math.min(50, discountPct(src) + rankDiscountPct(src, npc))
    return discounted(price, pct)
end

-- Price breakdown for the shop UI: base (after trader multiplier), member price (with discounts) and outsider price (with surcharge).
local function priceInfo(src, npc, base)
    local mult = tonumber(npc.priceMult) or 1.0
    local price = math.max(1, math.floor(base * mult + 0.5))
    local sur = tonumber(Traders.Settings.outsiderSurchargePct) or 25
    local pct = math.min(50, discountPct(src) + rankDiscountPct(src, npc))
    return {
        base = price,
        member = discounted(price, pct),
        outsider = math.max(1, math.floor(price * (100 + sur) / 100 + 0.5)),
    }
end

-- Rough category for rows saved without one.
local CAT_RULES = {
    { '^ammo_', 'ammo' }, { '^att_', 'weapons' }, { 'pistol', 'weapons' }, { 'rifle', 'weapons' },
    { 'shotgun', 'weapons' }, { 'smg', 'weapons' }, { 'knife', 'weapons' }, { 'machete', 'weapons' },
    { 'bandage', 'medical' }, { 'antiseptic', 'medical' }, { 'antibiotic', 'medical' }, { 'morphine', 'medical' },
    { 'medkit', 'medical' }, { 'pill', 'medical' }, { 'water', 'food' }, { 'food', 'food' }, { 'canned', 'food' },
    { 'ration', 'food' }, { 'toolbox', 'tools' }, { 'repair', 'tools' }, { 'lockpick', 'tools' }, { 'fuel', 'tools' },
    { 'scrap', 'materials' }, { 'wire', 'materials' }, { 'copper', 'materials' }, { 'cloth', 'materials' },
    { 'wood', 'materials' }, { 'teeth', 'materials' }, { 'shirt', 'clothing' }, { 'jacket', 'clothing' },
}
local function guessCategory(item)
    item = tostring(item or ''):lower()
    for _, r in ipairs(CAT_RULES) do
        if item:find(r[1]) then return r[2] end
    end
    return 'misc'
end

-- Category list for a trader: its own, or the defaults as { id, label = '' }.
local function categoriesOf(npc)
    if type(npc.categories) == 'table' and #npc.categories > 0 then return npc.categories end
    local out = {}
    for _, id in ipairs(Traders.DefaultCategories) do out[#out + 1] = { id = id, label = '' } end
    return out
end

-- True if a player is close enough to `npcId` to trade. Checked server-side against the server's own ped coords; staff editing via /traderdebug get a longer leash (see npcs:debug:save).
-- Horizontal distance with a separate, looser Z tolerance: the client ground-snaps the visible ped, so the configured Z can be off by a few metres.
-- On failure it prints the npc, the player position and the npc position to help debug.
local function nearNpc(src, npc)
    if not FlagNpcAllowed(src, npc.id) then return false end -- safezone flag NPCs: that faction only
    if denyReason(src, npc, true) then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local pos = GetEntityCoords(ped)
    local horizontal = #(vector2(pos.x, pos.y) - vector2(npc.coords.x, npc.coords.y))
    local vertical = math.abs(pos.z - npc.coords.z)

    local ok = horizontal <= (Traders.Settings.interactDistance + 3.0)   -- a little slack for lag
        and vertical <= 4.0   -- generous - ground-snap and authoring drift live here, not lag

    if not ok then
        print(('^1[bs_traders]^7 nearNpc(%s) failed - player at (%.2f, %.2f, %.2f), '
            .. 'npc at (%.2f, %.2f, %.2f) - horizontal %.2fm (limit %.2fm), vertical %.2fm (limit 4.00m)')
            :format(tostring(npc.id), pos.x, pos.y, pos.z,
                npc.coords.x, npc.coords.y, npc.coords.z,
                horizontal, Traders.Settings.interactDistance + 3.0, vertical))
    end

    return ok
end

-- Shared with sv_wardrobe.lua (same Lua state): the npc reach check and the transaction lock are published as globals so there is one copy.
NearNpc = nearNpc
WithTxLock = withTxLock

-- Seconds left before `missionId` can be accepted again, or 0. Elapsed time is computed in the query with TIMESTAMPDIFF, since oxmysql returns TIMESTAMP columns as formatted strings and parsing them needs a timezone assumption.
local function cooldownRemaining(charId, def)
    if not def then return 0 end

    local rows = exports.oxmysql:query_async(
        'SELECT TIMESTAMPDIFF(SECOND, `completed_at`, NOW()) AS `elapsed` '
        .. 'FROM `bs_npc_mission_log` WHERE `character_id` = ? AND `mission_id` = ? '
        .. 'ORDER BY `completed_at` DESC LIMIT 1',
        { charId, def.id }) or {}

    if not rows[1] then return 0 end

    local elapsed = tonumber(rows[1].elapsed) or 0
    return math.max(0, (def.cooldown or Traders.Settings.defaultCooldown) - elapsed)
end

-- Spawn list - public, every client needs it to place peds

-- Only enabled NPCs and only the fields a client needs to spawn one; prices and stock stay server-side. Re-requested by every client on 'bs:traders:reload'.
BSB.RegisterCallback('traders:list', function(src)
    local out = {}
    for _, id in ipairs(Registry.AllNpcIds()) do
        local npc = Registry.EffectiveNpc(id)
        if npc and not npc.disabled and FlagNpcAllowed(src, id) then
            out[#out + 1] = {
                id = npc.id, label = npc.label, role = npc.role,
                -- Drives the "Change Clothes" dot option in cl_peds.
                clothing = npc.clothing,
                model = npc.model, scenario = npc.scenario, heading = npc.heading,
                coords = { x = npc.coords.x, y = npc.coords.y, z = npc.coords.z },
                -- Blip only for those who may use the trader.
                blip = (npc.blipOn and not denyReason(src, npc, true)) and { sprite = npc.blipSprite, color = npc.blipColor } or nil,
            }
        end
    end
    return out
end)

-- Menu payload

-- Debug: reports which of the three checks rejected (no npc, disabled, too far) instead of one silent { ok = false }.
BSB.RegisterCallback('traders:open', function(src, npcId)
    -- Guarded: a throw here reaches the client as a bare nil (looks like a timeout). Registry.EffectiveNpc touches ZoneCoords and the override table and could throw too.
    local resolved, npc = pcall(Registry.EffectiveNpc, npcId)
    if not resolved then
        print(('^1[bs_traders]^7 traders:open(%s) threw in Registry.EffectiveNpc: %s')
            :format(tostring(npcId), tostring(npc)))
        return { ok = false, reason = ('server error resolving the npc: %s'):format(tostring(npc)) }
    end

    -- The rejection reason is sent back to the client (F8 console), not just the server console.
    if not npc then
        return { ok = false, reason = ('no such npc "%s" - EffectiveNpc returned nil '
            .. '(no config entry AND no database override for this id)'):format(tostring(npcId)) }
    end
    if npc.disabled then
        return { ok = false, reason = ('"%s" is marked disabled in its override'):format(tostring(npcId)) }
    end

    local dkey, dvars = denyReason(src, npc, npcHasRole(npc, 'trader'))
    if dkey then return { ok = false, reason = Lp(src, dkey, dvars) } end

    if not nearNpc(src, npc) then
        local ped = GetPlayerPed(src)
        local pos = ped and ped ~= 0 and GetEntityCoords(ped) or vector3(0, 0, 0)
        return { ok = false, reason = ('too far: player (%.1f, %.1f, %.1f) vs npc (%.1f, %.1f, %.1f) '
            .. '- %.1fm horizontal (limit %.1f), %.1fm vertical (limit 4.0)')
            :format(pos.x, pos.y, pos.z, npc.coords.x, npc.coords.y, npc.coords.z,
                #(vector2(pos.x, pos.y) - vector2(npc.coords.x, npc.coords.y)),
                Traders.Settings.interactDistance + 3.0,
                math.abs(pos.z - npc.coords.z)) }
    end

    -- Payload build is in its own pcall and the error text is sent back. A handler that throws is answered with nil by sh_bridge.lua, which the client sees as "timeout".
    -- Unguarded candidates: Stock.Get and exports.bs_inventory:CountItem.
    local built, payloadOrErr = pcall(function()

    local charId = charIdOf(src)
    local entry = State[src]

    local payload = { ok = true, npcId = npcId, label = npc.label, role = npc.role }
    local outsider = isOutsider(src, npc)
    if outsider then
        payload.outsider = true
        payload.surchargePct = tonumber(Traders.Settings.outsiderSurchargePct) or 25
    end

    if npcHasRole(npc, 'trader') then
        local sells = {}
        -- Use a label string, not the ItemBlurb table ({ label, rounds }), or the UI shows "[object Object]". Resolved here so the UI does not need to know another resource's export shape; falls back to the item id.
        local cats = categoriesOf(npc)
        for _, e in ipairs(npc.sells) do
            local stock = Stock.Get(npcId, e.item)
            local okBlurb, blurb = pcall(function() return exports.bs_inventory:ItemBlurb(e.item, src) end)
            local info = (okBlurb and type(blurb) == 'table') and blurb or nil
            local locked = not rankOk(src, npc, e)
            sells[#sells + 1] = {
                item = e.item, price = type(e.price) == 'number' and unitPrice(src, npc, e.price) or e.price,
                info = type(e.price) == 'number' and priceInfo(src, npc, e.price) or nil,
                category = e.category or guessCategory(e.item),
                locked = locked or nil, minRank = (tonumber(e.minRank) or 0) > 0 and e.minRank or nil,
                stock = stock,   -- nil = unlimited; the UI reads that as such
                label = (info and info.label) or e.item,
                rounds = info and info.rounds or nil,
            }
        end

        -- Buy rows get the same resolved label as sell rows.
        local buys = {}
        for _, e in ipairs(npc.buys) do
            local okBlurb, blurb = pcall(function() return exports.bs_inventory:ItemBlurb(e.item, src) end)
            local info = (okBlurb and type(blurb) == 'table') and blurb or nil
            local locked = not rankOk(src, npc, e)
            buys[#buys + 1] = {
                item = e.item, price = e.price,
                category = e.category or guessCategory(e.item),
                locked = locked or nil, minRank = (tonumber(e.minRank) or 0) > 0 and e.minRank or nil,
                label = (info and info.label) or e.item,
                have = exports.bs_inventory:CountItem(src, e.item),
            }
        end

        payload.sells = sells
        payload.buys  = buys
        payload.discount = {
            skill = discountPct(src),
            rank  = rankDiscountPct(src, npc),
            total = math.min(50, discountPct(src) + rankDiscountPct(src, npc)),
        }
        payload.categories = cats
        payload.cash  = cashOf(src)
    end

    if npcHasRole(npc, 'quest') and charId and not outsider then
        local missions = {}
        for _, missionId in ipairs(npc.missions) do
            local def = Registry.EffectiveMission(missionId)
            if def then
                local active = entry.missions[missionId]
                local status

                if active then
                    if def.kind == 'kill' then
                        status = active.progress >= def.target and 'ready' or 'active'
                    else
                        -- gather: readiness is whatever is in the bag right now.
                        status = exports.bs_inventory:CountItem(src, def.item) >= def.target
                                 and 'ready' or 'active'
                    end
                else
                    local cd = cooldownRemaining(charId, def)
                    status = cd > 0 and 'cooldown' or 'available'
                end

                missions[#missions + 1] = {
                    id = missionId, label = def.label, desc = def.desc,
                    kind = def.kind, target = def.target,
                    item = def.item,   -- nil for kill missions; fine
                    progress = active and (def.kind == 'kill' and active.progress
                               or exports.bs_inventory:CountItem(src, def.item)) or 0,
                    reward = def.reward, status = status,
                    cooldown = status == 'cooldown' and cooldownRemaining(charId, def) or nil,
                }
            end
        end
        payload.missions = missions
    end

    return payload

    end)   -- pcall

    if not built then
        print(('^1[bs_traders]^7 traders:open(%s) threw while building the menu payload: %s')
            :format(tostring(npcId), tostring(payloadOrErr)))
        return { ok = false, reason = ('server error building the menu: %s')
            :format(tostring(payloadOrErr)) }
    end

    return payloadOrErr
end)

-- Trading

BSB.RegisterCallback('traders:buy', function(src, npcId, item, qty)
    return withTxLock(src, function()
        local npc = Registry.EffectiveNpc(npcId)
        qty = math.floor(tonumber(qty) or 0)

        if not npc or npc.disabled or not npcHasRole(npc, 'trader') then
            return { ok = false, reason = 'unavailable' }
        end
        local dkey, dvars = denyReason(src, npc, true)
        if dkey then return { ok = false, reason = Lp(src, dkey, dvars) } end
        if not nearNpc(src, npc) then return { ok = false, reason = 'unavailable' } end
        if qty < 1 or qty > 99 then return { ok = false, reason = Lp(src, 'trd.e_qty') } end

        local entry = sellEntry(npc, item)
        if not entry then return { ok = false, reason = Lp(src, 'trd.e_not_sold') } end

        -- Price comes from Registry, but reject zero or negative prices (e.g. a staff typo via /traderdebug) so a buy can never pay the player.
        if type(entry.price) ~= 'number' or entry.price <= 0 then
            return { ok = false, reason = Lp(src, 'trd.e_not_sold') }
        end

        if not rankOk(src, npc, entry) then
            return { ok = false, reason = Lp(src, 'trd.e_rank', { n = entry.minRank }) }
        end

        local cost = unitPrice(src, npc, entry.price) * qty
        if cashOf(src) < cost then
            return { ok = false, reason = Lp(src, 'trd.e_cash') }
        end

        -- Stock first: if it fails, no money has moved.
        if not Stock.Take(npcId, item, qty) then
            return { ok = false, reason = Lp(src, 'trd.e_stock') }
        end

        -- GiveItem can fill some stacks and refuse the rest, and there is no "will it fit" check. Count before and after and take back exactly what went in on refusal.
        local before = exports.bs_inventory:CountItem(src, item)
        local given, label = exports.bs_inventory:GiveItem(src, item, qty)
        if not given then
            local added = exports.bs_inventory:CountItem(src, item) - before
            if added > 0 then exports.bs_inventory:RemoveItem(src, item, added) end
            -- Inventory refused (space/weight). Hand the stock back rather than charging.
            local shelf = Stock.Get(npcId, item)
            if shelf ~= nil then Stock.Take(npcId, item, -qty) end
            return { ok = false, reason = Lp(src, 'trd.e_space') }
        end

        -- RemoveMoney is checked: it is the last step and returns false if the player cannot pay. If it declines, the items and stock go back.
        if not exports.bs_core:RemoveMoney(src, 'cash', cost, 'npc_buy_' .. npcId) then
            exports.bs_inventory:RemoveItem(src, item, qty)
            local shelf = Stock.Get(npcId, item)
            if shelf ~= nil then Stock.Take(npcId, item, -qty) end
            return { ok = false, reason = Lp(src, 'trd.e_cash') }
        end

        return { ok = true, cash = cashOf(src),
                 stock = Stock.Get(npcId, item), bought = qty, label = label }
    end)
end)

BSB.RegisterCallback('traders:sell', function(src, npcId, item, qty)
    return withTxLock(src, function()
        local npc = Registry.EffectiveNpc(npcId)
        qty = math.floor(tonumber(qty) or 0)

        if not npc or npc.disabled or not npcHasRole(npc, 'trader') then
            return { ok = false, reason = 'unavailable' }
        end
        local dkey, dvars = denyReason(src, npc, true)
        if dkey then return { ok = false, reason = Lp(src, dkey, dvars) } end
        if not nearNpc(src, npc) then return { ok = false, reason = 'unavailable' } end
        if qty < 1 or qty > 999 then return { ok = false, reason = Lp(src, 'trd.e_qty') } end

        local entry = buyEntry(npc, item)
        if not entry then return { ok = false, reason = Lp(src, 'trd.e_not_bought') } end

        -- Same price check as npcs:buy.
        if type(entry.price) ~= 'number' or entry.price <= 0 then
            return { ok = false, reason = Lp(src, 'trd.e_not_bought') }
        end

        if not rankOk(src, npc, entry) then
            return { ok = false, reason = Lp(src, 'trd.e_rank', { n = entry.minRank }) }
        end

        if exports.bs_inventory:CountItem(src, item) < qty then
            return { ok = false, reason = Lp(src, 'trd.e_on_hand') }
        end

        -- Take the items first. RemoveItem only succeeds for the full amount, so there is nothing to unwind, and payment only happens after the items are gone.
        if not exports.bs_inventory:RemoveItem(src, item, qty) then
            return { ok = false, reason = Lp(src, 'trd.e_on_hand') }
        end

        local payout = entry.price * qty
        -- Checked: a payout that did not land hands the goods back.
        if not exports.bs_core:AddMoney(src, 'cash', payout, 'npc_sell_' .. npcId) then
            exports.bs_inventory:GiveItem(src, item, qty)
            return { ok = false, reason = Lp(src, 'trd.e_payment') }
        end

        return { ok = true, cash = cashOf(src), sold = qty }
    end)
end)

-- On-screen objective tracker. This is the server half: the authoritative list of active missions and progress, pushed to the client on every change.
-- GATHER counts are read live from the local inventory on the client (see cl_main.lua).

local function itemLabel(item, src)
    if not item then return nil end
    local ok, blurb = pcall(function() return exports.bs_inventory:ItemBlurb(item, src) end)
    if ok and type(blurb) == 'table' and blurb.label then return blurb.label end
    return item
end

local function trackerPayload(src)
    local entry = State[src]
    if not entry then return {} end

    local out = {}
    for missionId, active in pairs(entry.missions or {}) do
        local def = Registry.EffectiveMission(missionId)
        if def then
            out[#out + 1] = {
                id        = missionId,
                label     = def.label,
                desc      = def.desc,
                kind      = def.kind,
                target    = def.target,
                progress  = active.progress or 0,
                item      = def.item,
                itemLabel = itemLabel(def.item, src),
                reward    = def.reward,
            }
        end
    end
    return out
end

local function pushTracker(src)
    if not src then return end
    TriggerClientEvent('bs:traders:tracker', src, trackerPayload(src))
end

-- Missions

-- Offered by this NPC if it is in npc.missions (what the menu is built from); def.giver is only a fallback. /traderdebug writes npc.missions but not giver, so checking giver alone refused missions that were on display.
local function npcOffers(npc, missionId)
    for _, id in ipairs(npc.missions or {}) do
        if id == missionId then return true end
    end
    return false
end

-- One reason string per failed condition instead of a generic "unavailable"; app.js flash() shows it.
BSB.RegisterCallback('traders:missionAccept', function(src, npcId, missionId)
    return withTxLock(src, function()
        local npc = Registry.EffectiveNpc(npcId)
        local def = Registry.EffectiveMission(missionId)
        local charId = charIdOf(src)

        if not npc then return { ok = false, reason = 'no such npc: ' .. tostring(npcId) } end
        if npc.disabled then return { ok = false, reason = 'this npc is disabled' } end
        if not def then return { ok = false, reason = 'no such mission: ' .. tostring(missionId) } end
        if not charId then
            return { ok = false, reason = 'your character is not loaded server-side '
                .. '(restart bs_traders rebuilds this - see onResourceStart)' }
        end
        if not npcHasRole(npc, 'quest') then
            return { ok = false, reason = ('%s does not hand out work (role = %s)')
                :format(tostring(npcId), tostring(npc.role)) }
        end
        do
            local dkey, dvars = denyReason(src, npc)
            if dkey then return { ok = false, reason = Lp(src, dkey, dvars) } end
        end
        if not nearNpc(src, npc) then return { ok = false, reason = Lp(src, 'trd.e_far') } end
        if not npcOffers(npc, missionId) and def.giver ~= npcId then
            return { ok = false, reason = ('%s does not offer "%s" (its giver is %s)')
                :format(tostring(npcId), tostring(missionId), tostring(def.giver)) }
        end

        local entry = State[src]
        if entry.missions[missionId] then return { ok = false, reason = Lp(src, 'trd.e_active') } end
        if cooldownRemaining(charId, def) > 0 then return { ok = false, reason = 'cooldown' } end
        -- Grouped missions (e.g. rehab): one active at a time, shared cooldown.
        if def.group then
            for _, otherId in ipairs(Registry.AllMissionIds()) do
                local other = otherId ~= missionId and Registry.EffectiveMission(otherId)
                if other and other.group == def.group then
                    if entry.missions[otherId] then return { ok = false, reason = Lp(src, 'trd.e_job') } end
                    if cooldownRemaining(charId, other) > 0 then return { ok = false, reason = 'cooldown' } end
                end
            end
        end

        entry.missions[missionId] = { progress = 0, npcId = npcId }

        exports.oxmysql:execute_async(
            'INSERT INTO `bs_npc_missions` (`character_id`, `mission_id`, `npc_id`, `progress`) '
            .. 'VALUES (?, ?, ?, 0) ON DUPLICATE KEY UPDATE `progress` = 0, `npc_id` = VALUES(`npc_id`)',
            { charId, missionId, npcId })

        pushTracker(src)
        return { ok = true, missionId = missionId }
    end)
end)

BSB.RegisterCallback('traders:missionAbandon', function(src, npcId, missionId)
    return withTxLock(src, function()
        local charId = charIdOf(src)
        local entry = State[src]
        if not charId or not entry or not entry.missions[missionId] then
            return { ok = false, reason = Lp(src, 'trd.e_not_active') }
        end

        entry.missions[missionId] = nil
        exports.oxmysql:execute_async(
            'DELETE FROM `bs_npc_missions` WHERE `character_id` = ? AND `mission_id` = ?',
            { charId, missionId })

        pushTracker(src)
        return { ok = true }
    end)
end)

BSB.RegisterCallback('traders:missionTurnIn', function(src, npcId, missionId)
    return withTxLock(src, function()
        local npc = Registry.EffectiveNpc(npcId)
        local def = Registry.EffectiveMission(missionId)
        local charId = charIdOf(src)
        local entry = State[src]

        -- Same giver/offers rule as missionAccept: a mission you can accept from this NPC can also be handed in to it.
        if not npc then return { ok = false, reason = 'no such npc: ' .. tostring(npcId) } end
        if npc.disabled then return { ok = false, reason = 'this npc is disabled' } end
        if not def then return { ok = false, reason = 'no such mission: ' .. tostring(missionId) } end
        if not charId or not entry then
            return { ok = false, reason = Lp(src, 'trd.e_char') }
        end
        if not npcHasRole(npc, 'quest') then
            return { ok = false, reason = ('%s does not take work back (role = %s)')
                :format(tostring(npcId), tostring(npc.role)) }
        end
        do
            local dkey, dvars = denyReason(src, npc)
            if dkey then return { ok = false, reason = Lp(src, dkey, dvars) } end
        end
        if not nearNpc(src, npc) then return { ok = false, reason = Lp(src, 'trd.e_far') } end
        if not npcOffers(npc, missionId) and def.giver ~= npcId then
            return { ok = false, reason = ('%s does not handle "%s" (its giver is %s)')
                :format(tostring(npcId), tostring(missionId), tostring(def.giver)) }
        end

        local active = entry.missions[missionId]
        if not active then return { ok = false, reason = Lp(src, 'trd.e_not_active') } end

        if def.kind == 'kill' then
            if active.progress < def.target then return { ok = false, reason = Lp(src, 'trd.e_not_done') } end
        else
            -- GATHER: check and consume here in one place, so the items cannot be spent elsewhere between a menu check and the turn-in. txLock covers two rapid turn-ins.
            if exports.bs_inventory:CountItem(src, def.item) < def.target then
                return { ok = false, reason = Lp(src, 'trd.e_not_done') }
            end
            if def.consume then
                if not exports.bs_inventory:RemoveItem(src, def.item, def.target) then
                    return { ok = false, reason = Lp(src, 'trd.e_not_done') }
                end
            end
        end

        entry.missions[missionId] = nil
        exports.oxmysql:execute_async(
            'DELETE FROM `bs_npc_missions` WHERE `character_id` = ? AND `mission_id` = ?',
            { charId, missionId })
        exports.oxmysql:execute_async(
            'INSERT INTO `bs_npc_mission_log` (`character_id`, `mission_id`) VALUES (?, ?)',
            { charId, missionId })

        -- Same fix as the trade paths (see cashOf()). Rewards use the plain-data exports; a throw after consuming items would have lost the items and the mission with no reward.
        local reward = def.reward or {}
        if reward.xp    and reward.xp    > 0 then
            exports.bs_core:AddXP(src, reward.xp, 'npc_mission_' .. missionId)
        end
        if reward.money and reward.money > 0 then
            exports.bs_core:AddMoney(src, 'cash', reward.money, 'npc_mission_' .. missionId)
        end
        for _, it in ipairs(reward.items or {}) do
            pcall(function() exports.bs_inventory:GiveItem(src, it.item, it.amount or 1) end)
        end

        pushTracker(src)
        return { ok = true, reward = reward }
    end)
end)

-- Kill-mission progress

-- Fed by bs_core's reward pipeline (sv_rewards.lua), which fires this per zombie kill with the actionId a mission's `filter` lists. No hook into bs_zombies needed.
AddEventHandler('bs:hook:player:action', function(player, actionId)
    if not player or not player.source then return end
    local entry = State[player.source]
    if not entry then return end

    for missionId, active in pairs(entry.missions) do
        local def = Registry.EffectiveMission(missionId)
        if def and def.kind == 'kill' and active.progress < def.target then
            for _, id in ipairs(def.filter) do
                if id == actionId then
                    active.progress = active.progress + 1

                    -- Written through on every kill: at most one write per zombie death server-wide, similar to a reward payout.
                    exports.oxmysql:execute_async(
                        'UPDATE `bs_npc_missions` SET `progress` = ? '
                        .. 'WHERE `character_id` = ? AND `mission_id` = ?',
                        { active.progress, entry.charId, missionId })

                    TriggerClientEvent('bs:traders:progress', player.source,
                        missionId, active.progress, def.target)
                    break
                end
            end
        end
    end
end)

-- Trader editor (/traderdebug, F10, 'bs:traders:openEditor')

-- Every write is gated on isAdmin(src) again, in case the ace was lost mid-session or the callback was forged. Writes are logged to bs_guard_log.

BSB.RegisterCallback('traders:debug:list', function(src)
    if not isAdmin(src) then return { ok = false, reason = 'no permission' } end

    local npcs = {}
    for _, id in ipairs(Registry.AllNpcIds()) do npcs[#npcs + 1] = Registry.EffectiveNpc(id) end

    local missions = {}
    for _, id in ipairs(Registry.AllMissionIds()) do missions[#missions + 1] = Registry.EffectiveMission(id) end

    local zones = {}
    for _, z in ipairs(Traders.ListZones()) do
        zones[#zones + 1] = { id = z.id, label = z.label, x = z.coords.x, y = z.coords.y, z = z.coords.z }
    end

    return { ok = true, npcs = npcs, missions = missions, zones = zones,
             factions = Traders.Factions, defaultCategories = Traders.DefaultCategories }
end)

local function isNum(v) return type(v) == 'number' and v == v and v > -1e9 and v < 1e9 end
local function isInt(v) return isNum(v) and v == math.floor(v) end

-- Validates and cleans an editor patch. Returns clean patch, errors.
-- An error is { field, key, vars, row } where key is a ui.v_* locale key.
local function cleanNpcPatch(npcId, p)
    local out, errs = {}, {}
    local function err(field, key, vars, row) errs[#errs + 1] = { field = field, key = key, vars = vars, row = row } end

    local label = type(p.label) == 'string' and p.label:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if label == '' or #label > 48 then err('label', 'ui.v_label') end
    out.label = label

    if p.role ~= 'trader' and p.role ~= 'quest' and p.role ~= 'both' and p.role ~= 'clothing' then err('role', 'ui.v_role') end
    out.role = p.role

    if type(p.model) ~= 'string' or not p.model:match('^[%w_]+$') or #p.model > 64 then err('model', 'ui.v_model') end
    out.model = p.model
    out.scenario = type(p.scenario) == 'string' and p.scenario:sub(1, 64) or ''

    if not isNum(p.heading) or p.heading < -360 or p.heading > 720 then err('heading', 'ui.v_heading') end
    out.heading = tonumber(p.heading) or 0.0

    if not (isNum(p.x) and isNum(p.y) and isNum(p.z)) or p.z < -500 or p.z > 3000 then err('xyz', 'ui.v_coords') end
    out.x, out.y, out.z = p.x, p.y, p.z

    out.clothing = p.clothing and true or false
    out.disabled = p.disabled and true or false

    -- faction and zone
    local faction = type(p.faction) == 'string' and p.faction or ''
    if faction ~= '' then
        local okf = false
        for _, f in ipairs(Traders.Factions) do if f == faction then okf = true end end
        if not okf then err('faction', 'ui.v_faction') end
    end
    out.faction = faction
    local zone = type(p.safezone) == 'string' and p.safezone or ''
    if zone ~= '' and not Traders.FindZone(zone) then err('safezone', 'ui.v_zone') end
    out.safezone = zone

    -- categories
    local cats, catIds = {}, {}
    if type(p.categories) == 'table' then
        for i, c in ipairs(p.categories) do
            local id = type(c) == 'table' and type(c.id) == 'string' and c.id or ''
            local lb = type(c) == 'table' and type(c.label) == 'string' and c.label:sub(1, 24) or ''
            if not id:match('^[a-z0-9_]+$') or #id > 16 or catIds[id] or i > 16 then
                err('categories', 'ui.v_category_id', { id = id })
            else
                catIds[id] = true
                cats[#cats + 1] = { id = id, label = lb }
            end
        end
    end
    if #cats == 0 then
        for _, id in ipairs(Traders.DefaultCategories) do catIds[id] = true; cats[#cats + 1] = { id = id, label = '' } end
    end
    out.categories = cats

    -- trade rows
    local function cleanRows(list, field, selling)
        local rows, seen = {}, {}
        if type(list) ~= 'table' then return rows end
        for i, e in ipairs(list) do
            if type(e) ~= 'table' then err(field, 'ui.v_row', nil, i)
            else
                local item = type(e.item) == 'string' and e.item or ''
                local row = { item = item }
                local bad = false
                if not item:match('^[%w_%-]+$') or #item > 48 then err(field, 'ui.v_item', nil, i); bad = true end
                if seen[item] then err(field, 'ui.v_dup_item', { item = item }, i); bad = true end
                seen[item] = true
                if not isNum(e.price) or e.price <= 0 then err(field, 'ui.v_price', nil, i); bad = true end
                row.price = e.price
                if e.stock ~= nil then
                    if selling and isInt(e.stock) and e.stock >= 0 then row.stock = e.stock
                    elseif selling then err(field, 'ui.v_stock', nil, i); bad = true end
                end
                if selling and e.restockAmount ~= nil and e.restockAmount ~= 0 then
                    if isInt(e.restockAmount) and e.restockAmount > 0 then row.restockAmount = e.restockAmount
                    else err(field, 'ui.v_restock_amt', nil, i); bad = true end
                end
                if e.minRank ~= nil and e.minRank ~= 0 then
                    if isInt(e.minRank) and e.minRank >= 1 and e.minRank <= 10 then row.minRank = e.minRank
                    else err(field, 'ui.v_min_rank', nil, i); bad = true end
                end
                local cat = type(e.category) == 'string' and e.category or ''
                if cat == '' then cat = guessCategory(item); if not catIds[cat] then cat = cats[#cats].id end end
                if not catIds[cat] then err(field, 'ui.v_cat_unknown', { cat = cat }, i); bad = true end
                row.category = cat
                if not bad then rows[#rows + 1] = row end
            end
        end
        return rows
    end
    out.sells = cleanRows(p.sells, 'sells', true)
    out.buys = cleanRows(p.buys, 'buys', false)

    -- mission links must exist
    out.missions = {}
    if type(p.missions) == 'table' then
        for _, mid in ipairs(p.missions) do
            if type(mid) == 'string' and Registry.EffectiveMission(mid) then out.missions[#out.missions + 1] = mid end
        end
    end

    -- hours, price, restock, blip, notes
    local from, to = tonumber(p.openFrom), tonumber(p.openTo)
    if from == nil or to == nil then from, to = -1, -1 end
    if (from >= 0 or to >= 0) and (not isInt(from) or not isInt(to) or from < 0 or from > 23 or to < 0 or to > 23 or from == to) then
        err('hours', 'ui.v_hours')
    end
    out.openFrom, out.openTo = from, to

    local pm = tonumber(p.priceMult)
    if not pm or pm < 0.1 or pm > 10 then err('priceMult', 'ui.v_price_mult'); pm = 1.0 end
    out.priceMult = pm
    local rd = tonumber(p.rankDiscount) or 0
    if rd < 0 or rd > 15 then err('rankDiscount', 'ui.v_rank_disc'); rd = 0 end
    out.rankDiscount = rd
    local rs = tonumber(p.restock) or 0
    if rs ~= 0 and (not isInt(rs) or rs < 30 or rs > 604800) then err('restock', 'ui.v_restock') end
    out.restock = rs
    out.blipOn = p.blipOn and true or false
    local bs, bc = tonumber(p.blipSprite), tonumber(p.blipColor)
    if not isInt(bs) or bs < 1 or bs > 900 then err('blipSprite', 'ui.v_blip_sprite'); bs = 52 end
    if not isInt(bc) or bc < 0 or bc > 85 then err('blipColor', 'ui.v_blip_color'); bc = 2 end
    out.blipSprite, out.blipColor = bs, bc
    out.notes = type(p.notes) == 'string' and p.notes:sub(1, 300) or ''

    return out, errs
end

local function npcIdOk(id)
    return type(id) == 'string' and #id >= 2 and #id <= 48 and id:match('^[%w_%-]+$') ~= nil
end

-- `patch` is the editor form (see cleanNpcPatch). Server validates, saves, logs.
BSB.RegisterCallback('traders:debug:saveNpc', function(src, npcId, patch)
    if not isAdmin(src) then return { ok = false, reason = 'no permission' } end
    if type(patch) ~= 'table' then return { ok = false, reason = 'bad request' } end
    if not npcIdOk(npcId) then
        return { ok = false, errors = { { field = 'id', key = 'ui.v_id' } } }
    end

    local clean, errs = cleanNpcPatch(npcId, patch)
    if #errs > 0 then return { ok = false, errors = errs } end

    local existed = Registry.EffectiveNpc(npcId) ~= nil
    local npc = Registry.SetNpcOverride(npcId, clean)
    Stock.Reseed(npcId)   -- edited sells list gets a shelf to match
    guardLog(src, ('traders %s npc %s faction=%s zone=%s sells=%d buys=%d hours=%s-%s mult=%.2f'):format(
        existed and 'edit' or 'create', npcId, clean.faction ~= '' and clean.faction or 'none',
        clean.safezone ~= '' and clean.safezone or '-', #clean.sells, #clean.buys,
        clean.openFrom, clean.openTo, clean.priceMult))
    TriggerClientEvent('bs:traders:reload', -1)
    return { ok = true, npc = npc }
end)

-- Duplicate an NPC: copies the effective npc (config plus live overrides) into a new id at the caller's feet. It is a full override, and trade lists are deep-copied so edits never leak between the two.
local function deepCopy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepCopy(x) end
    return out
end

BSB.RegisterCallback('traders:debug:duplicateNpc', function(src, npcId, newId)
    if not isAdmin(src) then return { ok = false, reason = 'no permission' } end

    local source = Registry.EffectiveNpc(npcId)
    if not source then return { ok = false, reason = Lp(src, 'trd.e_no_npc') } end

    newId = tostring(newId or ''):gsub('%s+', '')
    if not npcIdOk(newId) then return { ok = false, reason = Lp(src, 'ui.v_id') } end
    if Registry.EffectiveNpc(newId) then
        return { ok = false, reason = Lp(src, 'ui.v_id_taken', { id = newId }) }
    end

    -- At the caller's feet, not on top of the original.
    local ped = GetPlayerPed(src)
    local pos = (ped and ped ~= 0) and GetEntityCoords(ped) or source.coords
    local heading = (ped and ped ~= 0) and GetEntityHeading(ped) or (source.heading or 0.0)

    local npc = Registry.SetNpcOverride(newId, {
        label    = (source.label or newId) .. ' (copy)',
        role     = source.role,
        model    = source.model,
        scenario = source.scenario or '',
        heading  = heading,
        x = pos.x, y = pos.y, z = pos.z,
        buys     = deepCopy(source.buys),
        sells    = deepCopy(source.sells),
        missions = deepCopy(source.missions),
        clothing = source.clothing and true or false,
        faction = source.faction or '', safezone = source.safezone or '',
        categories = deepCopy(source.categories),
        openFrom = source.openFrom, openTo = source.openTo, priceMult = source.priceMult,
        rankDiscount = source.rankDiscount, restock = source.restock,
        blipOn = source.blipOn, blipSprite = source.blipSprite, blipColor = source.blipColor,
        notes = source.notes or '',
        -- A copy starts disabled so it does not appear live before someone positions it. Untick `disabled` when ready.
        disabled = true,
    })
    Stock.Reseed(newId)
    guardLog(src, ('traders duplicate npc %s -> %s'):format(npcId, newId))

    TriggerClientEvent('bs:traders:reload', -1)
    return { ok = true, npc = npc }
end)

BSB.RegisterCallback('traders:debug:resetNpc', function(src, npcId)
    if not isAdmin(src) then return { ok = false, reason = 'no permission' } end
    if type(npcId) ~= 'string' then return { ok = false, reason = 'bad request' } end

    Registry.ResetNpc(npcId)
    Stock.Reseed(npcId)
    guardLog(src, ('traders reset/delete npc %s'):format(npcId))
    TriggerClientEvent('bs:traders:reload', -1)
    return { ok = true }
end)

BSB.RegisterCallback('traders:debug:saveMission', function(src, missionId, patch)
    if not isAdmin(src) then return { ok = false, reason = 'no permission' } end
    if type(missionId) ~= 'string' or missionId == '' or type(patch) ~= 'table' then
        return { ok = false, reason = 'bad request' }
    end

    local mission = Registry.SetMissionOverride(missionId, patch)
    guardLog(src, ('traders save mission %s'):format(missionId))
    return { ok = true, mission = mission }
end)

BSB.RegisterCallback('traders:debug:resetMission', function(src, missionId)
    if not isAdmin(src) then return { ok = false, reason = 'no permission' } end

    Registry.ResetMission(missionId)
    guardLog(src, ('traders reset/delete mission %s'):format(tostring(missionId)))
    return { ok = true }
end)

-- "Teleport this NPC to me", offered next to the manual x/y/z form.
BSB.RegisterCallback('traders:debug:here', function(src)
    if not isAdmin(src) then return { ok = false, reason = 'no permission' } end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { ok = false } end

    local pos = GetEntityCoords(ped)
    return { ok = true, x = pos.x, y = pos.y, z = pos.z,
             heading = GetEntityHeading(ped) }
end)

-- Reverse of npcs:debug:here: take the caller to this NPC. Needs isAdmin(), not isStaff() (see `teleportAces` in config_traders.lua). Coordinates come from Registry.EffectiveNpc, never the client.
BSB.RegisterCallback('traders:debug:teleport', function(src, npcId)
    if not isAdmin(src) then return { ok = false, reason = 'admins only' } end

    local npc = Registry.EffectiveNpc(npcId)
    if not npc or not npc.coords then return { ok = false, reason = 'no such npc' } end

    return { ok = true, x = npc.coords.x, y = npc.coords.y, z = npc.coords.z,
             heading = npc.heading or 0.0 }
end)

-- Lifecycle

AddEventHandler('bs:hook:player:loaded', function(player)
    if not player or not player.source then return end
    local src = player.source
    CreateThread(function()
        load(src, player.charId)
        -- The tracker has to survive a relog, not just a menu interaction.
        pushTracker(src)
    end)
end)

-- Rehydrate everyone already in the world. State[src] was only filled by the bs:hook:player:loaded handler, so restarting bs_traders left State empty and hid the Contracts tab (charId nil).
-- Rebuild it with GetPlayers() + GetPlayerSummary (charId is plain data).
AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    CreateThread(function()
        local restored = 0

        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)
            if src then
                local ok, summary = pcall(function()
                    return exports.bs_core:GetPlayerSummary(src)
                end)

                if ok and type(summary) == 'table' and summary.charId then
                    load(src, summary.charId)
                    pushTracker(src)
                    restored = restored + 1
                end
            end
        end

        if restored > 0 then
            print(('^2[bs_traders]^7 restored mission state for %d player(s) already in the world')
                :format(restored))
        end
    end)
end)

AddEventHandler('bs:hook:player:unloaded', function(player)
    if player and player.source then
        State[player.source] = nil
        txLock[player.source] = nil
    end
end)

AddEventHandler('playerDropped', function()
    State[source] = nil
    txLock[source] = nil
end)

-- Mission Log (bs_inventory): active trader quests. Turn-in is done at the quest giver, so there is no claim here.
exports('MissionLogList', function(src)
    src = tonumber(src)
    local entry = src and State[src]
    if not entry then return {} end
    local out = {}
    for missionId, active in pairs(entry.missions or {}) do
        local def = Registry.EffectiveMission(missionId)
        if def then
            local target = tonumber(def.target) or 1
            local have = active.progress or 0
            if def.kind ~= 'kill' then
                local ok, n = pcall(function() return exports.bs_inventory:CountItem(src, def.item) end)
                have = ok and tonumber(n) or 0
            end
            have = math.min(have, target)
            local done = have >= target
            out[#out + 1] = {
                id = 'trd:' .. tostring(missionId), title = def.label or missionId, group = Lp(src, 'mlog.trd_group'),
                steps = { { label = ('%s (%d/%d)'):format(def.label or missionId, have, target), done = done } },
                complete = done, claimed = false, noClaim = true,
                hint = Lp(src, def.kind == 'kill' and 'mlog.trd_kill' or 'mlog.trd_gather'),
            }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end)
exports('MissionLogClaim', function() return { ok = false } end)

local function registerLog()
    if GetResourceState('bs_inventory') == 'started' then
        pcall(function() exports.bs_inventory:RegisterMissionSource(GetCurrentResourceName()) end)
    end
end
CreateThread(function() Wait(1500); registerLog() end)
AddEventHandler('onResourceStart', function(res) if res == 'bs_inventory' then SetTimeout(1000, registerLog) end end)

-- bs_operations: where a quest NPC stands and which faction it serves (tag, flag owner, or the faction safezone it stands in).
exports('NpcInfo', function(npcId)
    local npc = Registry.EffectiveNpc(npcId)
    if not npc or npc.disabled or not npc.coords then return nil end
    local c = npc.coords
    local fid = npc.factionId or (npc.faction ~= '' and npc.faction) or nil
    if not fid then
        for _, z in ipairs((Zones and Zones.FactionSafe) or {}) do
            if z.enabled ~= false and z.coords then
                local inside
                if z.poly and Zones.InPoly then inside = Zones.InPoly(z.poly, c.x, c.y)
                else inside = #(vector2(c.x, c.y) - vector2(z.coords.x, z.coords.y)) <= (z.radius or 0.0) end
                if inside then fid = z.faction; break end
            end
        end
    end
    return { x = c.x, y = c.y, z = c.z, faction = fid, quest = npcHasRole(npc, 'quest') }
end)
