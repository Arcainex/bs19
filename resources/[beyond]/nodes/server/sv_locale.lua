-- Uses the existing bs_core server default and the central bs_atlas catalogs.
-- There is deliberately no nodes language setting or browser language choice.
NodesLocale = {}
local cache = {}
local function loadCatalog(lang)
    if cache[lang] then return cache[lang] end
    local source = LoadResourceFile('bs_atlas', 'locales/' .. lang .. '.lua')
    local dict = {}
    if source then
        local fn = load(source, '@bs_atlas/locales/' .. lang .. '.lua', 't', {})
        if fn then local ok, out = pcall(fn); if ok and type(out) == 'table' then dict = out end end
    end
    cache[lang] = dict
    return dict
end
function NodesLocale.Current()
    local lang = BSLocale.Default()
    local dict = {}
    for key, value in pairs(loadCatalog('en')) do dict[key] = value end
    if lang ~= 'en' then for key, value in pairs(loadCatalog(lang)) do dict[key] = value end end
    return {lang = lang, dict = dict}
end
function NodesLocale.T(key, vars)
    local lang = BSLocale.Default()
    local text = loadCatalog(lang)[key] or loadCatalog('en')[key] or key
    return (tostring(text):gsub('{([%w_]+)}', function(name)
        return vars and vars[name] ~= nil and tostring(vars[name]) or '{' .. name .. '}'
    end))
end
local rawKeys = {
    ['GET only'] = 'nodes.raw.get_only',
    ['sim disabled'] = 'nodes.raw.1',
    ['sim not ready'] = 'nodes.raw.2',
    ['not staff'] = 'nodes.raw.3',
    ['player position unavailable'] = 'nodes.raw.4',
    ['survey store missing (sv_atlas_points.lua)'] = 'nodes.raw.5',
    ['survey points are placed in game, where you stand'] = 'nodes.raw.6',
    ['no ped'] = 'nodes.raw.7',
    ['unknown survey action'] = 'nodes.raw.8',
    ['unknown terrain'] = 'nodes.raw.9',
    ['no such point - use add'] = 'nodes.raw.10',
    ['no such cell'] = 'nodes.raw.11',
    ['amount must be positive'] = 'nodes.raw.12',
    ['no editable cells in that rectangle'] = 'nodes.raw.13',
    ['x and y required'] = 'nodes.raw.14',
    ['too many observers'] = 'nodes.raw.15',
    ['unknown atlas op'] = 'nodes.raw.16',
    ['no such section'] = 'nodes.raw.17',
    ['not a number'] = 'nodes.raw.18',
    ['not writable'] = 'nodes.raw.19',
    ['id must be letters, numbers, _ or -, 40 max'] = 'nodes.raw.20',
    ['bs_zombies is not running'] = 'nodes.raw.21',
    ['AtlasCall returned nothing'] = 'nodes.raw.22',
    ['bad JSON body'] = 'nodes.raw.23',
    ['POST only'] = 'nodes.raw.24',
    ['bad body'] = 'nodes.raw.25',
    ['that field cannot be set'] = 'nodes.raw.26',
    ['no image in that'] = 'nodes.raw.27',
    ['that file is empty or not an image'] = 'nodes.raw.28',
    ['not a PNG, JPEG or WebP'] = 'nodes.raw.29',
    ['that box is inside out'] = 'nodes.raw.30',
    ['calibration.json is unreadable.'] = 'nodes.raw.31',
    ['calibration.json is inside out.'] = 'nodes.raw.32',
    ['calibration.json not found - using the default box; alignment NOT verified.'] = 'nodes.raw.33',
    ['nodes/html/img/map.png is missing on the server.'] = 'nodes.raw.34',
    ['html/img/map.png is missing'] = 'nodes.raw.35',
    ['no map image'] = 'nodes.raw.36',
    ['Forbidden.\n'] = 'nodes.raw.37',
    ['Not found.\n'] = 'nodes.raw.38',
    ['retired: the herd simulation was replaced. The atlas now uses /api/snapshot (see sv_http.lua WEB ATLAS).'] = 'nodes.raw.39',
}
function NodesLocale.Text(text)
    if type(text) ~= 'string' then return text end
    if rawKeys[text] then return NodesLocale.T(rawKeys[text]) end
    local value = text:match('^clamped to (.+)$')
    if value then return NodesLocale.T('nodes.msg.clamped', {value = value}) end
    value = text:match('^calibration%.json is missing (.+)%.$')
    if value then return NodesLocale.T('nodes.msg.missing_bound', {field = value}) end
    value = text:match('^bad (minX)$') or text:match('^bad (maxX)$') or text:match('^bad (minY)$') or text:match('^bad (maxY)$')
    if value then return NodesLocale.T('nodes.msg.bad_field', {field = value}) end
    value = text:match('^server error in atlas (.+)$')
    if value then return NodesLocale.T('nodes.msg.server_error', {operation = value}) end
    return text -- Preserve technical details and unknown future error codes.
end
function NodesLocale.Response(data)
    if type(data) ~= 'table' then return data end
    local out = {}; for key, value in pairs(data) do out[key] = value end
    out.error = NodesLocale.Text(out.error); out.note = NodesLocale.Text(out.note)
    if type(out.map) == 'table' then out.map = NodesLocale.Response(out.map) end
    if type(out.rejected) == 'table' then
        local translated = {}; for key, value in pairs(out.rejected) do translated[key] = NodesLocale.Text(value) end
        out.rejected = translated
    end
    return out
end
