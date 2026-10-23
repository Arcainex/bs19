-- bs_traders - clothing shop authority. The client browses and previews; the server decides: who the player is (VIP, level), what they own (bought garments stay owned, bills count only new ones), and whether they may buy this (re-checked on every purchase).
-- Money moves only here, through bs_core's source-taking exports (see cashOf() in sv_traders.lua for why object methods do not survive exports).

-- Storage
-- Two tables. bs_core already persists the current outfit; this file never writes it. It stores the two lists:
-- owned: every (category, drawable) the character has paid for. Only grows; checked server-side.
-- outfits: saved sets by name, limited to owned garments, so wearing one is free.
-- Created at start with CREATE TABLE IF NOT EXISTS because this resource owns its schema (see sv_registry.lua).

CreateThread(function()
    exports.oxmysql:execute_async([[
        CREATE TABLE IF NOT EXISTS `bs_wardrobe_owned` (
            `char_id`  INT NOT NULL,
            `category` VARCHAR(24) NOT NULL,
            `drawable` INT NOT NULL,
            PRIMARY KEY (`char_id`, `category`, `drawable`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    exports.oxmysql:execute_async([[
        CREATE TABLE IF NOT EXISTS `bs_wardrobe_outfits` (
            `id`      INT NOT NULL AUTO_INCREMENT,
            `char_id` INT NOT NULL,
            `name`    VARCHAR(32) NOT NULL,
            `data`    TEXT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `char` (`char_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end)

--------------------------------------------------------------------------------
-- Who is asking
--------------------------------------------------------------------------------

-- Facts the gate needs. bs_vip is optional, so IsVIP is called through a resource-state check; without it there are simply no VIP items (never treat everyone as VIP).
-- `charId` keys everything below; with no character loaded every path refuses.
local function identify(src)
    local vip = false
    if GetResourceState('bs_vip') == 'started' then
        local ok, answer = pcall(function() return exports.bs_vip:IsVIP(src) end)
        vip = (ok and answer) and true or false
    end

    local level, charId, gender = 0, nil, 'male'
    local ok, summary = pcall(function() return exports.bs_core:GetPlayerSummary(src) end)
    if ok and type(summary) == 'table' then
        level = tonumber(summary.level) or 0
        charId = tonumber(summary.charId)
        gender = summary.gender == 'female' and 'female' or 'male'
    end

    -- VIP extras: more outfit slots and a tailor discount (bs_vip config).
    local outfitBonus, discount = 0, 0
    if GetResourceState('bs_vip') == 'started' then
        pcall(function()
            outfitBonus = math.floor(tonumber(exports.bs_vip:PerkValue(src, 'tailorOutfits', 'bonus', 0)) or 0)
            discount = math.floor(tonumber(exports.bs_vip:PerkValue(src, 'tailorDiscount', 'pct', 0)) or 0)
        end)
    end
    discount = math.max(0, math.min(90, discount))

    return { vip = vip, level = level, charId = charId, gender = gender,
             maxOutfits = Wardrobe.Outfits.maxPerCharacter + math.max(0, outfitBonus), discount = discount }
end

local function cashOf(src)
    local ok, summary = pcall(function() return exports.bs_core:GetPlayerSummary(src) end)
    if not ok or type(summary) ~= 'table' then return 0 end
    return (summary.accounts and summary.accounts.cash) or 0
end

--------------------------------------------------------------------------------
-- Ownership
--------------------------------------------------------------------------------

-- Ownership is per drawable, not per texture: buying a jacket unlocks every colour, so the colour arrows are not a trap. Price the garment, give the wardrobe.
local function ownedKeys(charId)
    if not charId then return {} end

    local rows = exports.oxmysql:query_async(
        'SELECT `category`, `drawable` FROM `bs_wardrobe_owned` WHERE `char_id` = ?',
        { charId }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = ('%s:%d'):format(row.category, row.drawable)
    end
    return out
end

local function recordOwned(charId, category, drawable)
    if not charId or drawable < 0 then return end
    exports.oxmysql:execute_async(
        'INSERT IGNORE INTO `bs_wardrobe_owned` (`char_id`, `category`, `drawable`) VALUES (?, ?, ?)',
        { charId, category, drawable })
end

local function ownsSet(charId)
    local set = {}
    for _, key in ipairs(ownedKeys(charId)) do set[key] = true end
    return set
end

--------------------------------------------------------------------------------
-- Saved outfits
--------------------------------------------------------------------------------

local function outfitsOf(charId)
    if not charId then return {} end

    local rows = exports.oxmysql:query_async(
        'SELECT `id`, `name`, `data` FROM `bs_wardrobe_outfits` WHERE `char_id` = ? ORDER BY `id`',
        { charId }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        local ok, data = pcall(json.decode, row.data)
        -- A row that will not decode is skipped instead of returned empty, so it can be re-saved.
        if ok and type(data) == 'table' then
            out[#out + 1] = { id = row.id, name = row.name, parts = data }
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- Opening the shop
--------------------------------------------------------------------------------

-- Shared by both entry points: the npc exists, sells clothes and the player is standing at it. Returns nil, reason otherwise.
local function shopNpc(src, npcId)
    local npc = Registry.EffectiveNpc(npcId)
    if not npc then return nil, 'no such npc: ' .. tostring(npcId) end
    if npc.disabled then return nil, 'this npc is disabled' end
    -- A dedicated tailor, or anyone with the `clothing` flag. 'both' is not accepted: it means trader+quest here.
    if npc.role ~= 'clothing' and not npc.clothing then
        return nil, ('%s does not sell clothes (role = %s, clothing = %s)')
            :format(tostring(npcId), tostring(npc.role), tostring(npc.clothing))
    end
    if not NearNpc(src, npc) then return nil, 'too far from them' end
    return npc
end

-- What the panel needs that the client cannot work out. Not a catalogue: the client knows its own ped's drawable counts. Returns the rules (categories, prices, player status, owned items) and the client draws against them.
-- `rules` is sent whole so locked rows can be shown as 'VIP' or 'level 15' instead of hidden.
BSB.RegisterCallback('wardrobe:open', function(src, npcId)
    local npc, why = shopNpc(src, npcId)
    if not npc then return { ok = false, reason = why } end

    local who = identify(src)

    return {
        ok = true,
        npcId = npcId,
        label = npc.label,
        cash = cashOf(src),
        vip = who.vip,
        level = who.level,
        gender = who.gender,
        owned = ownedKeys(who.charId),
        outfits = outfitsOf(who.charId),
        maxOutfits = who.maxOutfits,
        discount = who.discount,
        categories = Wardrobe.Categories,
        bare = Wardrobe.Bare,
        rules = Wardrobe.Rules,
        basePrice = Wardrobe.Settings.basePrice,
        cam = { distance = Wardrobe.Settings.camDistance, height = Wardrobe.Settings.camHeight },
    }
end)

--------------------------------------------------------------------------------
-- Buying
--------------------------------------------------------------------------------

-- Confirm a whole fitting at once. `changes` is a list of { category, drawable, texture }, only what the player altered (diffed against the outfit snapshotted when the shop opened).
-- One transaction: everything is priced and authorised first, money moves once, then the client is told to keep what it wears. Uses the per-player transaction lock so a double-clicked Confirm cannot bill twice.
BSB.RegisterCallback('wardrobe:buy', function(src, npcId, changes)
    return WithTxLock(src, function()
        local npc, why = shopNpc(src, npcId)
        if not npc then return { ok = false, reason = why } end

        if type(changes) ~= 'table' or #changes == 0 then
            return { ok = false, reason = 'nothing changed' }
        end
        -- Sane ceiling: there are fourteen categories, anything past that is a malformed payload.
        if #changes > 28 then return { ok = false, reason = 'too many changes' } end

        local who = identify(src)
        local owns = ownsSet(who.charId)
        local total = 0
        local toRecord = {}

        for _, change in ipairs(changes) do
            local categoryId = tostring(change.category or '')
            local drawable = math.floor(tonumber(change.drawable) or -1)

            local cat = Wardrobe.ByCategory[categoryId]
            if not cat then
                return { ok = false, reason = ('unknown category: %s'):format(categoryId) }
            end

            -- Taking something off is free. Components have no empty state, so the client resolves 'none' to the model's bare drawable (Wardrobe.BareFor) before it gets here; -1 only reaches this for props (ClearPedProp). Nobody is charged for undressing.
            if drawable < 0 then
                if cat.kind ~= 'prop' then
                    return { ok = false, reason = ('%s: removal was not resolved'):format(cat.label) }
                end
            else
                local allowed, reason = Wardrobe.Allowed(categoryId, drawable, who)
                if not allowed then
                    return { ok = false, reason = ('%s: %s'):format(cat.label, reason) }
                end

                -- The bare body is not a garment and is never sold, so removing a jacket does not cost a jacket.
                local bare = Wardrobe.BareFor(categoryId, who.gender)
                local free = (bare ~= nil and drawable == bare)
                    or owns[('%s:%d'):format(categoryId, drawable)]

                if not free then
                    total = total + Wardrobe.PriceFor(categoryId, drawable)
                    toRecord[#toRecord + 1] = { categoryId, drawable }
                end
            end
        end

        -- VIP tailor discount, rounded down to whole dollars
        if total > 0 and (who.discount or 0) > 0 then
            total = math.floor(total * (100 - who.discount) / 100)
        end

        if total > 0 then
            if cashOf(src) < total then
                return { ok = false, reason = ('you need $%d'):format(total) }
            end
            if not exports.bs_core:RemoveMoney(src, 'cash', total, 'wardrobe_' .. tostring(npcId)) then
                return { ok = false, reason = 'payment failed' }
            end
        end

        -- Recorded only after the money moved. Writing rows first would grant permanent ownership when payment fails.
        for _, entry in ipairs(toRecord) do
            recordOwned(who.charId, entry[1], entry[2])
        end

        -- The outfit itself is not written here. The client is already wearing it and bs_core's outfit layer persists it ('bs:outfit:push' -> CaptureOutfit -> character metadata); a second server-side copy would drift.
        -- The server only confirms 'paid for, allowed' and tells the client to keep what it has on.
        return {
            ok = true,
            spent = total,
            cash = cashOf(src),
            owned = ownedKeys(who.charId),
        }
    end)
end)

--------------------------------------------------------------------------------
-- Outfits
--------------------------------------------------------------------------------

-- Save what is on the ped, by name. `parts` is { category = { drawable, texture } }. Refused unless every garment is owned or bare, so an outfit is never a way to acquire clothes and wearing one needs no price check.
BSB.RegisterCallback('wardrobe:outfitSave', function(src, npcId, name, parts)
    local npc, why = shopNpc(src, npcId)
    if not npc then return { ok = false, reason = why } end

    local who = identify(src)
    if not who.charId then return { ok = false, reason = 'no character loaded' } end

    name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then return { ok = false, reason = 'name it something' } end
    if #name > Wardrobe.Outfits.nameMaxLength then
        name = name:sub(1, Wardrobe.Outfits.nameMaxLength)
    end

    if type(parts) ~= 'table' then return { ok = false, reason = 'malformed outfit' } end

    local owns = ownsSet(who.charId)
    local clean = {}

    for categoryId, part in pairs(parts) do
        local cat = Wardrobe.ByCategory[categoryId]
        local drawable = math.floor(tonumber(part and part.drawable) or -1)
        local texture = math.max(0, math.floor(tonumber(part and part.texture) or 0))

        if cat then
            local bare = Wardrobe.BareFor(categoryId, who.gender)
            local ok = drawable < 0
                or (bare ~= nil and drawable == bare)
                or owns[('%s:%d'):format(categoryId, drawable)]

            if not ok then
                return { ok = false, reason = ('%s is not yours yet - buy it first'):format(cat.label) }
            end

            clean[categoryId] = { drawable = drawable, texture = texture }
        end
    end

    local existing = outfitsOf(who.charId)

    -- Saving over a name replaces it, so there are never two outfits with the same label.
    for _, outfit in ipairs(existing) do
        if outfit.name:lower() == name:lower() then
            exports.oxmysql:execute_async(
                'UPDATE `bs_wardrobe_outfits` SET `data` = ? WHERE `id` = ? AND `char_id` = ?',
                { json.encode(clean), outfit.id, who.charId })
            return { ok = true, replaced = true, outfits = outfitsOf(who.charId) }
        end
    end

    if #existing >= who.maxOutfits then
        return { ok = false, reason = ('you can keep %d outfits - delete one first')
            :format(who.maxOutfits) }
    end

    exports.oxmysql:execute_async(
        'INSERT INTO `bs_wardrobe_outfits` (`char_id`, `name`, `data`) VALUES (?, ?, ?)',
        { who.charId, name, json.encode(clean) })

    return { ok = true, outfits = outfitsOf(who.charId) }
end)

BSB.RegisterCallback('wardrobe:outfitDelete', function(src, outfitId)
    local who = identify(src)
    if not who.charId then return { ok = false, reason = 'no character loaded' } end

    -- char_id in the WHERE clause too: the id comes from the client and must not reach another character's row.
    exports.oxmysql:execute_async(
        'DELETE FROM `bs_wardrobe_outfits` WHERE `id` = ? AND `char_id` = ?',
        { math.floor(tonumber(outfitId) or -1), who.charId })

    return { ok = true, outfits = outfitsOf(who.charId) }
end)

-- What may be saved as worn. Classifies each shop piece of a sanitised outfit with the same rules as wardrobe:buy (bare is free, locked is refused, price 0 is free); ownership is checked by the caller against bs_wardrobe_owned. Stops previewing a paid or VIP piece and disconnecting from keeping it.
-- Returns a list of { kind, index, category, drawable, bare, verdict } (verdict 'free' | 'paid' | 'locked') plus the charId. Categories the shop does not sell (face, hair) are not listed.
exports('ClassifyOutfit', function(src, outfit)
    if type(outfit) ~= 'table' then return {}, nil end
    local who = identify(src)
    local out = {}

    for _, cat in ipairs(Wardrobe.Categories) do
        local bucket = outfit.components
        if cat.kind == 'prop' then bucket = outfit.props end
        local v = type(bucket) == 'table' and bucket[tostring(cat.index)]

        if type(v) == 'table' then
            local drawable = math.floor(tonumber(v.drawable) or -1)
            local bare = Wardrobe.BareFor(cat.id, who.gender)
            local verdict = 'paid'

            if (bare ~= nil and drawable == bare) or (cat.kind == 'prop' and drawable < 0) then
                verdict = 'free'
            elseif not Wardrobe.Allowed(cat.id, drawable, who) then
                verdict = 'locked'
            elseif Wardrobe.PriceFor(cat.id, drawable) <= 0 then
                verdict = 'free'
            end

            out[#out + 1] = { kind = cat.kind, index = cat.index, category = cat.id,
                              drawable = drawable, bare = bare, verdict = verdict }
        end
    end

    return out, who.charId
end)
