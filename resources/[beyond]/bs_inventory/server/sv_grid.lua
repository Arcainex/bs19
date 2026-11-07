-- bs_inventory - 2D grid placement: where an item sits in a container.
-- Pure geometry (no state, database or natives), so it can be tested off-server.
-- NOTE: not wired in yet, nothing in sv_main calls it.
-- Coordinates are 1-based, (1,1) is top-left; 0 in the database means 'not placed'.
-- An entry is { id, w, h, rot }; a rotated item swaps its footprint (1x3 -> 3x1)
-- and footprint() is the only place that happens.

Grid = Grid or {}

-- Geometry

--- The space an entry actually takes, accounting for rotation.
--- @return integer w, integer h
function Grid.Footprint(entry)
    local w = entry.w or 1
    local h = entry.h or 1
    if entry.rot then return h, w end
    return w, h
end

-- Do two axis-aligned rectangles overlap? They miss if one is entirely left of,
-- right of, above or below the other.
local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
    if ax + aw - 1 < bx then return false end
    if bx + bw - 1 < ax then return false end
    if ay + ah - 1 < by then return false end
    if by + bh - 1 < ay then return false end
    return true
end

Grid.Overlaps = overlaps

-- Fitting

-- Can `entry` sit with its top-left at (x, y)?
-- `ignoreId` lets an item be moved onto cells it currently occupies; pass the
-- id when repositioning. Returns false plus a reason (off the edge vs no room).
-- @return boolean ok, string? reason
function Grid.Fits(container, entries, entry, x, y, ignoreId)
    local w, h = Grid.Footprint(entry)

    if type(x) ~= 'number' or type(y) ~= 'number' then return false, 'bad position' end
    if x < 1 or y < 1 then return false, 'off the grid' end
    if x + w - 1 > container.width  then return false, 'too wide there' end
    if y + h - 1 > container.height then return false, 'too tall there' end

    for _, other in pairs(entries) do
        if other.id ~= ignoreId and other.x and other.y then
            local ow, oh = Grid.Footprint(other)
            if overlaps(x, y, w, h, other.x, other.y, ow, oh) then
                return false, 'something is in the way'
            end
        end
    end

    return true
end

-- First free spot, scanning left to right then top to bottom. Rotation is a
-- second pass over the whole grid, so items stay upright wherever possible.
-- @return integer? x, integer? y, boolean rotated
function Grid.FirstFit(container, entries, entry, allowRotate)
    local upright = { w = entry.w, h = entry.h, rot = false }

    for y = 1, container.height do
        for x = 1, container.width do
            if Grid.Fits(container, entries, upright, x, y, entry.id) then
                return x, y, false
            end
        end
    end

    if allowRotate ~= false and (entry.w or 1) ~= (entry.h or 1) then
        local turned = { w = entry.w, h = entry.h, rot = true }
        for y = 1, container.height do
            for x = 1, container.width do
                if Grid.Fits(container, entries, turned, x, y, entry.id) then
                    return x, y, true
                end
            end
        end
    end

    return nil, nil, false
end

-- Occupancy, for the UI and diagnostics

-- A width x height map of which entry id owns each cell, nil for empty.
-- Indexed [y][x].
function Grid.Occupancy(container, entries)
    local map = {}
    for y = 1, container.height do
        map[y] = {}
        for x = 1, container.width do map[y][x] = false end
    end

    for _, e in pairs(entries) do
        if e.x and e.y then
            local w, h = Grid.Footprint(e)
            for yy = e.y, math.min(e.y + h - 1, container.height) do
                for xx = e.x, math.min(e.x + w - 1, container.width) do
                    map[yy][xx] = e.id
                end
            end
        end
    end

    return map
end

-- How many cells are free. Cheaper than Occupancy when only the count matters.
function Grid.FreeCells(container, entries)
    local used = 0
    for _, e in pairs(entries) do
        if e.x and e.y then
            local w, h = Grid.Footprint(e)
            used = used + (w * h)
        end
    end
    return (container.width * container.height) - used
end

-- Repair

-- Existing items have slot_y = 0 (not placed), so this re-packs a container
-- from scratch, biggest first. Anything that does not fit is returned as
-- overflow, never dropped; the caller decides what to do with it.
-- @return table placed, table overflow
function Grid.Repack(container, entries)
    local order = {}
    for _, e in pairs(entries) do order[#order + 1] = e end

    table.sort(order, function(a, b)
        local aw, ah = Grid.Footprint(a)
        local bw, bh = Grid.Footprint(b)
        local areaA, areaB = aw * ah, bw * bh
        if areaA ~= areaB then return areaA > areaB end
        -- Stable tiebreak so repacking the same contents is deterministic.
        return tostring(a.id) < tostring(b.id)
    end)

    local placed, overflow = {}, {}

    for _, e in ipairs(order) do
        local candidate = { id = e.id, w = e.w, h = e.h, rot = false }
        local x, y, rotated = Grid.FirstFit(container, placed, candidate, true)

        if x then
            e.x, e.y, e.rot = x, y, rotated
            placed[#placed + 1] = e
        else
            overflow[#overflow + 1] = e
        end
    end

    return placed, overflow
end

return Grid
