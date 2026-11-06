-- Faction emblem spec: what may be stored. The drawing lives in bs_ui/html/shared/emblem.js; keep these id lists in step with it.

Emblem = {}

local function set(list) local s = {}; for _, v in ipairs(list) do s[v] = true end; return s end

Emblem.Shapes   = set({ 'heater', 'kite', 'round', 'patch', 'circle', 'hex', 'octagon', 'diamond', 'square', 'pennant', 'cog', 'triangle', 'dogtag', 'roundel' })
Emblem.Patterns = set({ 'none', 'halves', 'fess', 'quarters', 'per_bend', 'bend', 'chevron', 'chief', 'pales', 'bars', 'cross', 'saltire', 'orle', 'rays', 'hazard', 'checker', 'camo', 'dots' })
Emblem.Symbols  = set({ 'skull', 'skull_bones', 'ram_skull', 'wolf', 'crow', 'snake', 'wings', 'winged_wheel', 'eagle', 'star', 'star_ring', 'compass', 'chevrons', 'crossed_rifles', 'crosshair', 'bullets', 'dagger', 'axes', 'hammer', 'wrenches', 'gear', 'pistons', 'wheel', 'flame', 'bolt', 'biohazard', 'radiation', 'fist', 'hand', 'crown', 'eye', 'anchor', 'sprout', 'tree', 'house', 'tower', 'mountain', 'medical', 'heart', 'key', 'warning' })
Emblem.Borders  = set({ 'none', 'thin', 'thick', 'double', 'rivets', 'stitched', 'barbed' })
Emblem.Wear     = set({ 'none', 'scuffed', 'weathered', 'battered', 'burnt', 'rust' })
Emblem.TagMax   = 4
Emblem.MaxJson  = 400

local function hex(v)
    v = type(v) == 'string' and v:lower() or ''
    return v:match('^#%x%x%x%x%x%x$') and v or nil
end

-- Returns a clean copy, or nil and a reason. Nothing outside the lists gets through.
function Emblem.Validate(spec)
    if type(spec) == 'string' then
        if #spec > Emblem.MaxJson * 2 then return nil, 'too_long' end
        local ok, d = pcall(json.decode, spec)
        spec = ok and d or nil
    end
    if type(spec) ~= 'table' then return nil, 'not_a_table' end
    local out = {
        v = 1,
        shape = Emblem.Shapes[spec.shape] and spec.shape or nil,
        pattern = Emblem.Patterns[spec.pattern] and spec.pattern or nil,
        symbol = Emblem.Symbols[spec.symbol] and spec.symbol or nil,
        border = Emblem.Borders[spec.border] and spec.border or nil,
        wear = Emblem.Wear[spec.wear] and spec.wear or nil,
        primary = hex(spec.primary), secondary = hex(spec.secondary), accent = hex(spec.accent),
    }
    for _, k in ipairs({ 'shape', 'pattern', 'symbol', 'border', 'wear', 'primary', 'secondary', 'accent' }) do
        if not out[k] then return nil, 'bad_' .. k end
    end
    local tag = spec.tag
    if tag ~= nil and type(tag) ~= 'string' then return nil, 'bad_tag' end
    tag = (tag or ''):upper()
    if #tag > Emblem.TagMax or tag:find('[^A-Z0-9]') then return nil, 'bad_tag' end
    out.tag = tag
    return out
end

function Emblem.Encode(spec) return json.encode(spec) end
