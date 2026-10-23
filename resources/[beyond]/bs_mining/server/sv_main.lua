-- bs_mining - rock ownership.
-- The server owns a node as a place, keyed by rounded world position (like bs_interactions bins), because props are not networked and handles differ per client.
-- The client's node name is only a claim: it is verified against the player's position at swing start and at collect.

local S = Mining.Settings

--------------------------------------------------------------------------------
-- Node state
--------------------------------------------------------------------------------

-- [key] = { left, type, emptyUntil }
-- Created lazily; untouched rocks have no entry. The sweep below drops refilled nodes so the table stays small.
local nodes = {}

local function parseKey(key)
    if type(key) ~= 'string' or #key > 64 then return nil end
    local x, y, z = key:match('^(%-?%d+%.?%d*):(%-?%d+%.?%d*):(%-?%d+%.?%d*)$')
    if not x then return nil end
    return tonumber(x), tonumber(y), tonumber(z)
end

--- The claim check. Everything else here assumes it has passed.
local function near(src, key)
    local x, y, z = parseKey(key)
    if not x then return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local c = GetEntityCoords(ped)
    local dx, dy, dz = c.x - x, c.y - y, c.z - z
    return math.sqrt(dx * dx + dy * dy + dz * dz) <= (S.proximity + 2.0)
end

local function swingsFor(def)
    local range = def.swings or { 4, 6 }
    local lo = math.floor(range[1] or 4)
    local hi = math.floor(range[2] or lo)
    if hi <= lo then return lo end
    return math.random(lo, hi)
end

--- Reads a node's state, creating it if this is the first swing at it, and
--- refilling it if its respawn has passed.
local function nodeAt(key, typeId)
    local def = Mining.Types[typeId]
    if not def then return nil end

    local node = nodes[key]
    local now = os.time()

    if node and node.left <= 0 then
        if now >= (node.emptyUntil or 0) then
            node.left = swingsFor(def)
            node.emptyUntil = nil
        end
    end

    if not node then
        node = { left = swingsFor(def), type = typeId }
        nodes[key] = node
    end

    return node
end

-- Forgetting. A node that refilled long ago is indistinguishable from one
-- nobody has touched, so keeping the row costs memory and buys nothing.
CreateThread(function()
    while true do
        Wait(300000)
        local now = os.time()
        for key, node in pairs(nodes) do
            if node.left > 0 and (not node.emptyUntil or now > node.emptyUntil + 600) then
                nodes[key] = nil
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Tools
--------------------------------------------------------------------------------

-- First tool from def.tools (or def.tool) the player carries.
local function toolOf(src, def)
    for _, t in ipairs(def.tools or { def.tool }) do
        local ok, count = pcall(function() return exports.bs_inventory:CountItem(src, t) end)
        if ok and (tonumber(count) or 0) >= 1 then return t end
    end
    return nil
end

local function hasTool(src, def)
    if not def.tool and not def.tools then return true end
    return toolOf(src, def) ~= nil
end

--------------------------------------------------------------------------------
-- Yield
--------------------------------------------------------------------------------

local function skillBonus(src)
    if not S.skill or GetResourceState('bs_skills') ~= 'started' then return 0.0 end

    local ok, level = pcall(function() return exports.bs_skills:GetSkillLevel(src, S.skill) end)
    if not ok or type(level) ~= 'number' then return 0.0 end

    return math.min((S.maxBonus or 0.4), level * (S.bonusPerLevel or 0.02))
end

-- One swing's yield: base roll plus a skill-based chance of one extra unit (not a multiplier, so levels help a little instead of dominating).
local function yieldFor(src, def)
    local bonus = skillBonus(src)
    local out = {}

    for _, entry in ipairs(def.yield or {}) do
        local range = entry.amount or { 1, 1 }
        local lo, hi = math.floor(range[1] or 1), math.floor(range[2] or range[1] or 1)
        local count = (hi > lo) and math.random(lo, hi) or lo

        if bonus > 0 and math.random() < bonus then count = count + 1 end
        if entry.chance and math.random() > entry.chance then count = 0 end
        if count > 0 then out[#out + 1] = { item = entry.item, amount = count } end
    end

    return out
end

--------------------------------------------------------------------------------
-- Swinging
--------------------------------------------------------------------------------

local working = {}     -- [key] = src, one pair of hands per node
local started = {}     -- [src] = { key, type, at }

BSB.RegisterCallback('mining:start', function(src, typeId, key)
    if not S.enabled then return { ok = false, error = Lp(src, 'mn.off') } end

    local def = Mining.Types[typeId]
    if not def then return { ok = false, error = Lp(src, 'mn.cant_work') } end
    if not near(src, key) then return { ok = false, error = Lp(src, 'mn.far') } end

    if working[key] and working[key] ~= src then
        return { ok = false, error = Lp(src, 'mn.busy') }
    end

    if not hasTool(src, def) then
        return { ok = false, error = Lp(src, 'mn.need', { tool = def.toolLabel or def.tool }) }
    end

    local node = nodeAt(key, typeId)
    if not node then return { ok = false } end

    if node.left <= 0 then
        local left = math.max(0, (node.emptyUntil or 0) - os.time())
        return { ok = false,
                 error = ('Worked out. Another %d min.'):format(math.max(1, math.ceil(left / 60))) }
    end

    working[key] = src
    -- Milliseconds, from the game clock. os.time() has one-second resolution,
    -- which is not enough to tell a 2.6s animation from a 1.9s one.
    started[src] = { key = key, type = typeId, at = GetGameTimer() }

    return { ok = true, swingMs = S.swingMs, left = node.left }
end)

-- The swing lands. Items are handed over at the end of the animation, so a player killed, downed or disconnected mid-swing gets nothing.
-- Proximity is checked again here to prove the player was still there.
BSB.RegisterCallback('mining:swing', function(src, typeId, key)
    local claim = started[src]
    if not claim or claim.key ~= key or claim.type ~= typeId then
        return { ok = false, error = Lp(src, 'mn.not_working') }
    end

    -- A swing that lands sooner than the animation could possibly finish is a
    -- client that skipped the animation.
    if GetGameTimer() - claim.at < (S.swingMs or 2600) - 400 then
        return { ok = false, error = Lp(src, 'mn.too_fast') }
    end

    started[src] = nil
    working[key] = nil

    if not near(src, key) then return { ok = false, error = Lp(src, 'mn.walked') } end

    local def = Mining.Types[typeId]
    local node = nodes[key]
    if not def or not node or node.left <= 0 then
        return { ok = false, error = Lp(src, 'mn.empty') }
    end

    if not hasTool(src, def) then
        return { ok = false, error = Lp(src, 'mn.need', { tool = def.toolLabel or def.tool }) }
    end

    node.left = node.left - 1
    local exhausted = node.left <= 0
    if exhausted then
        node.emptyUntil = os.time() + (S.respawnSeconds or 600)
    end

    -- Wear the tool BEFORE handing over the materials: a swing that breaks the
    -- pickaxe still produced its stone, and the player should be told in that
    -- order.
    local broke = false
    local tool = toolOf(src, def)
    if tool and def.wear and def.wear > 0 then
        local ok, _, didBreak = pcall(function()
            return exports.bs_inventory:WearItem(src, tool, def.wear)
        end)
        broke = ok and didBreak or false
    end

    local given = {}
    for _, entry in ipairs(yieldFor(src, def)) do
        local ok, label = exports.bs_inventory:GiveItem(src, entry.item, entry.amount)
        given[#given + 1] = {
            item = entry.item, amount = entry.amount,
            label = (type(label) == 'string' and label) or entry.item,
            -- A full bag is not a silent failure. The material is lost - the
            -- rock is still worked - and the player is told why.
            spilled = not ok,
        }
    end

    if S.skill and S.xpPerSwing and GetResourceState('bs_skills') == 'started' then
        pcall(function() exports.bs_skills:AddSkillXP(src, S.skill, S.xpPerSwing) end)
    end

    return { ok = true, given = given, left = node.left, exhausted = exhausted, broke = broke }
end)

--- Somebody stopped early. Free the node rather than leaving it reserved to a
--- player who is no longer swinging at it.
BSB.RegisterCallback('mining:abort', function(src, key)
    if working[key] == src then working[key] = nil end
    started[src] = nil
    return { ok = true }
end)

AddEventHandler('playerDropped', function()
    local src = source
    local claim = started[src]
    if claim and working[claim.key] == src then working[claim.key] = nil end
    started[src] = nil
end)

--------------------------------------------------------------------------------
-- Admin
--------------------------------------------------------------------------------

BSB.RegisterCommand('minednodes', 'bs.admin', 'How many gathering nodes are being tracked',
    {}, function(src)
        local total, empty = 0, 0
        for _, node in pairs(nodes) do
            total = total + 1
            if node.left <= 0 then empty = empty + 1 end
        end

        local line = ('%d node(s) tracked, %d worked out'):format(total, empty)
        if src > 0 then
            TriggerClientEvent('bs:ui:notify', src, { type = 'info', message = line })
        else print(line) end
    end)

exports.bs_core:RegisterModule('mining', { side = 'server', version = '0.1.0' })
