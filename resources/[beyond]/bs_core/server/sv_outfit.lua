-- BeyondSurvival - saves clothing and last weapon into character metadata for the select-screen preview.

local MAX_COMPONENT = 11
local MAX_PROP      = 7

-- Component 5 is the parachute pack and is never chosen by the framework. Dropped here too, so rows that already hold one get cleaned on the next push (see cl_outfit.lua).
local PARACHUTE_COMPONENT = 5

-- Rebuilds a client-supplied outfit from scratch, keeping only well-formed numeric entries in range. Never trust the client's shape.
local function sanitize(outfit)
    if type(outfit) ~= 'table' then return nil end
    local clean = { components = {}, props = {} }

    for id, v in pairs(outfit.components or {}) do
        local n = tonumber(id)
        if n and n >= 0 and n <= MAX_COMPONENT and n ~= PARACHUTE_COMPONENT
            and type(v) == 'table' then
            clean.components[tostring(math.floor(n))] = {
                drawable = math.max(0, math.floor(tonumber(v.drawable) or 0)),
                texture  = math.max(0, math.floor(tonumber(v.texture) or 0)),
                palette  = math.max(0, math.floor(tonumber(v.palette) or 2)),
            }
        end
    end

    for id, v in pairs(outfit.props or {}) do
        local n = tonumber(id)
        if n and n >= 0 and n <= MAX_PROP and type(v) == 'table' then
            local drawable = math.floor(tonumber(v.drawable) or -1)
            clean.props[tostring(math.floor(n))] = {
                drawable = drawable < -1 and -1 or drawable,
                texture  = math.max(-1, math.floor(tonumber(v.texture) or -1)),
            }
        end
    end

    return clean
end

-- Only paid-for pieces are kept. Shop pieces are checked with bs_traders' buy rules (bare / free / owned in bs_wardrobe_owned); a failing piece keeps the previously saved value or falls back to bare.
local function withoutUnpaid(src, player, clean)
    if GetResourceState('bs_traders') ~= 'started' then return clean end

    local ok, pieces, charId = pcall(function()
        return exports.bs_traders:ClassifyOutfit(src, clean)
    end)
    if not ok or type(pieces) ~= 'table' then return nil end

    local owned = nil
    local prev = player:GetMeta('outfit') or {}

    for _, piece in ipairs(pieces) do
        local key = tostring(piece.index)
        local bucket, prevBucket = clean.components, prev.components
        if piece.kind == 'prop' then bucket, prevBucket = clean.props, prev.props end
        local before = type(prevBucket) == 'table' and prevBucket[key] or nil

        local keep = piece.verdict == 'free'
        if not keep and before and tonumber(before.drawable) == piece.drawable then
            keep = true   -- unchanged since last save: already accepted then
        end
        if not keep and piece.verdict == 'paid' and charId then
            if not owned then
                owned = {}
                local rows = exports.oxmysql:query_async(
                    'SELECT `category`, `drawable` FROM `bs_wardrobe_owned` WHERE `char_id` = ?',
                    { charId }) or {}
                for _, row in ipairs(rows) do owned[('%s:%d'):format(row.category, row.drawable)] = true end
            end
            keep = owned[('%s:%d'):format(piece.category, piece.drawable)] == true
        end

        if not keep then
            if before then
                bucket[key] = before
            elseif piece.kind == 'prop' then
                bucket[key] = { drawable = -1, texture = -1 }
            elseif piece.bare ~= nil then
                bucket[key] = { drawable = piece.bare, texture = 0, palette = 2 }
            else
                bucket[key] = nil
            end
        end
    end

    return clean
end

RegisterNetEvent(BS.Events.UpdateOutfit, function(outfit, weapon)
    local src = source
    local player = BS.GetPlayer(src)
    if not player then return end

    local clean = sanitize(outfit)
    if not clean then return end

    clean = withoutUnpaid(src, player, clean)
    if not clean then return end

    -- Face (0) and hair (2) are appearance, not clothes: only a ticket edit may change them, so keep the saved values.
    local prevComps = (player:GetMeta('outfit') or {}).components
    for _, k in ipairs({ '0', '2' }) do
        clean.components[k] = type(prevComps) == 'table' and prevComps[k] or nil
    end

    player:SetMeta('outfit', clean)
    if weapon then
        player:SetMeta('lastWeapon', math.floor(tonumber(weapon) or 0))
    end

    -- Written immediately instead of waiting for the autosave, so a crash right after buying clothes cannot lose them. Outfit changes are rare, so the extra write is cheap.
    player:Save(true)
end)
