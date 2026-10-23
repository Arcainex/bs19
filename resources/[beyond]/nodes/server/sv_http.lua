-- bs_sectormap - sector panel served over HTTP on the server's existing web port (same as txAdmin). Ensure the resource and read the URL from the console. A key is generated on first boot; the map image is dragged onto the page. The port is internet-facing and the panel can edit zombie sectors, so remote requests need the key.

local KEY_FILE = 'panel_key.txt'
local RES = GetCurrentResourceName()

-- Generated once and saved. 32 random hex characters; the clock only seeds it.
local function generateKey()
    math.randomseed((os.time() * 1000) + math.floor(GetGameTimer()))
    for _ = 1, 8 do math.random() end          -- shake off the weak first draws

    local out = {}
    for i = 1, 32 do out[i] = ('%x'):format(math.random(0, 15)) end
    return table.concat(out)
end

local resolvedKey = nil

local function token()
    if resolvedKey then return resolvedKey end

    -- An explicit convar always wins.
    local fromCfg = GetConvar('bs_sectormap_key', '')
    if fromCfg ~= '' and fromCfg ~= 'CHANGE-ME' and #fromCfg >= 12 then
        resolvedKey = fromCfg
        return resolvedKey
    end

    local saved = LoadResourceFile(RES, KEY_FILE)
    if saved then saved = saved:gsub('%s+', '') end
    if saved and #saved >= 12 then
        resolvedKey = saved
        return resolvedKey
    end

    resolvedKey = generateKey()
    SaveResourceFile(RES, KEY_FILE, resolvedKey, -1)
    return resolvedKey
end

-- Always true. Kept as a function so the handler reads well and a future build can refuse.
local function configured() return #token() >= 12 end

-- Localhost needs no key: anyone on the host already has the console and files. Remote requests still need it. req.address is the peer address, so it cannot be spoofed by a header.
local function isLocal(req)
    local addr = tostring(req.address or '')
    -- Comes with a port attached, e.g. 127.0.0.1:52344.
    addr = addr:match('^%[?([^%]]*)%]?:%d+$') or addr
    return addr == '127.0.0.1' or addr == '::1' or addr == 'localhost'
        or addr:match('^127%.') ~= nil
end

-- Constant-time-ish comparison; never returns early on a mismatch.
local function tokenMatches(given)
    if type(given) ~= 'string' then return false end

    local want = token()
    if #given ~= #want then return false end

    local diff = 0
    for i = 1, #want do
        diff = diff | (string.byte(want, i) ~ string.byte(given, i))
    end
    return diff == 0
end

-- Request helpers

local function query(path)
    local out = {}
    local q = path:match('%?(.*)$')
    if not q then return out end

    for pair in q:gmatch('[^&]+') do
        local k, v = pair:match('^([^=]+)=?(.*)$')
        if k then
            -- Percent decoding, so a token with symbols in it survives the URL.
            v = (v or ''):gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
            out[k] = v:gsub('%+', ' ')
        end
    end
    return out
end

local function send(res, status, body, mime)
    res.writeHead(status, {
        ['Content-Type'] = mime or 'application/json; charset=utf-8',
        -- Nothing here is cacheable: the whole point is live state.
        ['Cache-Control'] = 'no-store',
        -- This panel is only ever opened directly. Refusing to be framed
        -- costs nothing and removes a whole class of clickjacking.
        ['X-Frame-Options'] = 'DENY',
        ['X-Content-Type-Options'] = 'nosniff',
    })
    res.send(body)
end

local function json_(res, status, tbl)
    send(res, status, json.encode(tbl))
end

-- The map image
-- The game's map art is not shipped. Drag a screenshot onto the page or paste with Ctrl+V; it is saved here and served back. Cached in memory since it is a few megabytes.

local MAP_FILE  = 'html/img/map.dat'    -- extension-free: the mime is stored beside it
local MIME_FILE = 'html/img/map.mime'
local MAX_MAP   = 12 * 1024 * 1024

local mapCache, mapMime, mapChecked = nil, nil, false

local function mapImage()
    if mapChecked then return mapCache, mapMime end
    mapChecked = true

    -- Panel upload first.
    local data = LoadResourceFile(RES, MAP_FILE)
    if data and #data > 0 then
        mapCache = data
        mapMime = (LoadResourceFile(RES, MIME_FILE) or 'image/png'):gsub('%s+', '')
        return mapCache, mapMime
    end

    -- Then anything dropped in by hand.
    for _, c in ipairs({
        { file = 'html/img/map.jpg', mime = 'image/jpeg' },
        { file = 'html/img/map.png', mime = 'image/png'  },
    }) do
        local d = LoadResourceFile(RES, c.file)
        if d and #d > 0 then
            mapCache, mapMime = d, c.mime
            return mapCache, mapMime
        end
    end

    return nil, nil
end

-- Base64 written out here (about twenty lines) rather than pulling a dependency. Characters outside the alphabet are skipped, which tolerates newlines in data: URLs.
local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local B64_LOOKUP = {}
for i = 1, #B64 do B64_LOOKUP[B64:sub(i, i)] = i - 1 end

local function b64decode(input)
    input = input:gsub('[^' .. B64 .. '=]', '')

    local out, bits, count = {}, 0, 0
    for i = 1, #input do
        local c = input:sub(i, i)
        if c ~= '=' then
            local v = B64_LOOKUP[c]
            if v then
                bits = (bits << 6) | v
                count = count + 6
                if count >= 8 then
                    count = count - 8
                    out[#out + 1] = string.char((bits >> count) & 0xFF)
                end
            end
        end
    end
    return table.concat(out)
end

-- Where the picture sits, in world metres. The image is stretched across this box. Saved rather than hardcoded since every crop is different.
local CALIB_FILE = 'calibration.json'
local DEFAULT_CALIB = { minX = -4498, maxX = 5220, minY = -5272, maxY = 8819 }  -- fits the shipped map.png (about 11.3 m per pixel)

local function calibration()
    local raw = LoadResourceFile(RES, CALIB_FILE)
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' and data.minX then return data end
    end
    return DEFAULT_CALIB
end

-- Talking to bs_zombies
-- These exports are pure table work and never yield, which makes them safe to call from this handler (see bs_zombies/server/sv_sectors.lua).

local function zombies()
    if GetResourceState('bs_zombies') ~= 'started' then return nil end
    return exports.bs_zombies
end

-- Web atlas - the in-game /atlas in a browser, on the real map, admin only. The page is built per request from bs_atlas files: html/index.html, css/style.css (inlined), js/host-web.js (web transport, inlined first), js/map.js (renderer) and js/app.js.

--- nil for GET-able read ops, true for POST-only ops.
local ATLAS_OPS = {
    snapshot = false, inspect = false,
    edit = true, repopulate = true, observe = true, config = true,
}

-- Plain-text find/replace: string.gsub would treat '%' in the inlined JS/CSS as a capture reference.
local function replacePlain(hay, needle, with)
    local i, j = hay:find(needle, 1, true)
    if not i then return hay, false end
    return hay:sub(1, i - 1) .. with .. hay:sub(j + 1), true
end

-- A closing script tag inside inlined JS would end the element early. None exist today; this keeps it that way.
local function scriptSafe(js) return (js:gsub('</script', '<\\/script')) end

local function atlasPage()
    local files = {}
    for _, f in ipairs({ 'html/index.html', 'html/css/style.css', 'html/js/host-web.js',
                         'html/js/map.js', 'html/js/app.js' }) do
        local body = LoadResourceFile('bs_atlas', f)
        if not body or body == '' then
            return nil, ('The web atlas is built from bs_atlas/%s and that file could not be read.\n'
                .. 'Is the bs_atlas resource in the resources folder?\n'):format(f)
        end
        files[f] = body
    end

    local page, ok = files['html/index.html'], nil

    page, ok = replacePlain(page, '<link rel="stylesheet" href="css/style.css" />',
        '<style>\n/* inlined from bs_atlas/html/css/style.css by nodes/server/sv_http.lua */\n'
        .. files['html/css/style.css']
        -- A browser tab has no game under it: opaque background and the panel shown immediately.
        .. '\nhtml,body{background:#07090c;}\n</style>')
    if not ok then return nil, 'bs_atlas/html/index.html no longer has the style.css <link> this handler replaces.' end

    page, ok = replacePlain(page, '<script src="js/map.js"></script>',
        '<script>/* inlined from bs_atlas/html/js/host-web.js */\n' .. scriptSafe(files['html/js/host-web.js']) .. '\n</script>\n'
        .. '<script>/* inlined from bs_atlas/html/js/map.js */\n' .. scriptSafe(files['html/js/map.js']) .. '\n</script>')
    if not ok then return nil, 'bs_atlas/html/index.html no longer has the map.js <script> this handler replaces.' end

    page, ok = replacePlain(page, '<script src="js/app.js"></script>',
        '<script>/* inlined from bs_atlas/html/js/app.js */\n' .. scriptSafe(files['html/js/app.js']) .. '\n</script>')
    if not ok then return nil, 'bs_atlas/html/index.html no longer has the app.js <script> this handler replaces.' end

    return page
end

local mapPngCache = nil
local function atlasMapPng()
    if mapPngCache then return mapPngCache end
    local d = LoadResourceFile(RES, 'html/img/map.png')
    if d and #d > 0 then mapPngCache = d end
    return mapPngCache
end

-- Calibration as the atlas uses it (same rules as bs_atlas sv_atlas.lua): file missing -> default box with an unverified note; file broken -> no box, image not drawn; file fine -> its four numbers.
local function atlasCalibration()
    local raw = LoadResourceFile(RES, CALIB_FILE)
    if not raw or raw == '' then
        return DEFAULT_CALIB, 'calibration.json not found - using the default box; alignment NOT verified.'
    end
    local ok, d = pcall(json.decode, raw)
    if not ok or type(d) ~= 'table' then return nil, 'calibration.json is unreadable.' end
    local c = {}
    for _, k in ipairs({ 'minX', 'maxX', 'minY', 'maxY' }) do
        local v = tonumber(d[k])
        if not v or v ~= v then return nil, 'calibration.json is missing ' .. k .. '.' end
        c[k] = v
    end
    if c.maxX <= c.minX or c.maxY <= c.minY then return nil, 'calibration.json is inside out.' end
    return c, nil
end

-- Everything the page needs before its first snapshot, same as cl_atlas.lua's 'open' message. World box and place names come from ZAtlas (bs_zombies/config/config_atlas.lua, included by this fxmanifest like bs_atlas); viewer settings mirror config_atlas_ui.lua defaults.
local function atlasBoot()
    local points = {}
    if type(ZAtlas) == 'table' and type(ZAtlas.points) == 'table' then
        for i = 1, #ZAtlas.points do
            local p = ZAtlas.points[i]
            points[i] = { id = p.id, x = p.x, y = p.y, d = p.d, t = p.t }
        end
    end
    local world = (type(ZAtlas) == 'table' and type(ZAtlas.bounds) == 'table') and ZAtlas.bounds
        or { minX = -4000.0, maxX = 5000.0, minY = -4000.0, maxY = 8000.0 }

    local calib, note = atlasCalibration()
    local map
    if atlasMapPng() then
        map = { path = 'img/map.png', calib = calib, note = note }
    else
        map = { error = 'nodes/html/img/map.png is missing on the server.' }
    end

    return {
        ok = true,
        world = world,
        points = points,
        map = map,
        simRunning = GetResourceState('bs_zombies') == 'started',
        cfg = {
            pollMs = 1000,           -- a browser tab is often left open, so poll less often than in game
            pollMsMin = 250, pollMsMax = 5000,
            staleAfterPolls = 2,
            openSpanMetres = 3000.0, minSpanMetres = 120.0, maxSpanMetres = 16000.0,
            fetchMargin = 0.15,
            observerRadius = 300, observerRadiusMin = 50, observerRadiusMax = 1200,
            observerRefreshSeconds = 100,
        },
    }
end

local function peer(req)
    return tostring(req.address or 'unknown address')
end

-- One-line bounded description of a mutation for the console.
local function describe(op, a)
    if op == 'edit' then
        return ('cell %s,%s patch=%s'):format(tostring(a.cx), tostring(a.cy),
            (pcall(json.encode, a.patch) and json.encode(a.patch or {}) or '?'))
    elseif op == 'repopulate' then
        return ('+%s in rect %s,%s .. %s,%s'):format(tostring(a.amount), tostring(a.x1),
            tostring(a.y1), tostring(a.x2), tostring(a.y2))
    elseif op == 'observe' then
        return (a.on == false) and 'clear web observer'
            or ('web observer at %s,%s r=%s'):format(tostring(a.x), tostring(a.y), tostring(a.radius))
    elseif op == 'config' then
        return type(a.patch) == 'table' and ('patch=' .. json.encode(a.patch)) or 'read'
    end
    return ''
end

local function runOp(res, op, args, who)
    if GetResourceState('bs_zombies') ~= 'started' then
        return json_(res, 503, { ok = false, error = 'bs_zombies is not running' })
    end
    local ok, out = pcall(function() return exports.bs_zombies:AtlasCall(op, args, who) end)
    if not ok then
        -- Most likely bs_zombies is running an older sv_sim_atlas.lua without AtlasCall. Say that.
        return json_(res, 503, { ok = false,
            error = 'bs_zombies has no AtlasCall export (is sv_sim_atlas.lua up to date?): ' .. tostring(out) })
    end
    if type(out) ~= 'table' then
        return json_(res, 502, { ok = false, error = 'AtlasCall returned nothing' })
    end
    -- Encoded under pcall: `config` returns live Sim tables, and a non-serialisable value must give an error, not a hanging request.
    local encOk, body = pcall(json.encode, out)
    if not encOk then
        return json_(res, 500, { ok = false, error = 'could not encode the answer: ' .. tostring(body) })
    end
    return send(res, 200, body)
end

local function atlasApi(req, res, op)
    local postOnly = ATLAS_OPS[op]
    local method = req.method or 'GET'

    if method ~= 'POST' then
        if postOnly then
            return json_(res, 405, { ok = false, error = op .. ' changes the world: POST only' })
        end
        -- Read-only op over GET: args may come as ?a=<json>, else none.
        local a = {}
        local raw = query(req.path or '').a
        if raw and raw ~= '' then
            local ok, d = pcall(json.decode, raw)
            if ok and type(d) == 'table' then a = d end
        end
        return runOp(res, op, a, peer(req))
    end

    -- setDataHandler delivers the body in a callback, so the reply must be sent from inside it (see /api/set below).
    req.setDataHandler(function(body)
        local a = {}
        if body and body ~= '' then
            local ok, d = pcall(json.decode, body)
            if not ok or type(d) ~= 'table' then
                return json_(res, 400, { ok = false, error = 'bad JSON body' })
            end
            a = d
        end

        if postOnly and not (op == 'config' and type(a.patch) ~= 'table') then
            -- Audit line, printed before the call so a change that throws half-way is still logged. Only the peer address is known; the panel key is shared.
            print(('^3[nodes]^7 web atlas %s from %s (panel key holder - the key does not identify a person): %s')
                :format(op, peer(req), describe(op, a)))
        end

        return runOp(res, op, a, peer(req))
    end)
end

-- The handler

SetHttpHandler(function(req, res)
    -- FiveM strips the resource prefix, so `path` starts at our own root.
    local path = (req.path or '/'):gsub('//+', '/')
    local route = path:match('^([^?]*)') or '/'
    local args = query(path)

    -- A key always exists (token() generates one). This only fires if the resource cannot write its own folder.
    if not configured() then
        return send(res, 500,
            'bs_sectormap could not create its access key.\n\n'
            .. 'That usually means the resource folder is read-only. Give the\n'
            .. 'server write access to it, or set one yourself in server.cfg:\n\n'
            .. '    set bs_sectormap_key "your-long-random-token"\n',
            'text/plain; charset=utf-8')
    end

    if not (isLocal(req) or tokenMatches(args.key)) then
        -- A wrong key gets a flat refusal. A missing key is usually the owner typing the address by hand, so that case gets directions on where to find the key (not the key itself).
        if args.key == nil then
            return send(res, 401,
                'SECTOR MAP\n\n'
                .. 'This page needs its access key, and the address you used has\n'
                .. 'none on the end of it.\n\n'
                .. 'The full link is printed in your SERVER CONSOLE at startup,\n'
                .. 'in a framed box. It looks like:\n\n'
                .. '    http://your-server:' .. GetConvar('netPort', '30120')
                .. '/' .. RES .. '/?key=<32 characters>\n\n'
                .. 'In game, an admin can type /sectormap to have it sent to chat.\n\n'
                .. 'From the machine the server itself runs on, no key is needed -\n'
                .. 'so if you meant to do that, check you are on localhost and not\n'
                .. 'the LAN address.\n',
                'text/plain; charset=utf-8')
        end

        return send(res, 403, 'Forbidden.\n', 'text/plain; charset=utf-8')
    end

    -- The page: node atlas in the browser. '/' is what http://host:30120/nodes arrives as; '/nodes' and the .html names are kept so old bookmarks land here. html/nodes.html (the old herd page) is no longer served.
    if route == '/' or route == '/index.html' or route == '/nodes' or route == '/nodes.html' then
        local page, why = atlasPage()
        if not page then return send(res, 500, why, 'text/plain; charset=utf-8') end
        return send(res, 200, page, 'text/html; charset=utf-8')
    end

    -- The real map: html/img/map.png only. The /map route below prefers an uploaded map.dat or map.jpg, but the atlas must show the same picture in game (nui://nodes/html/img/map.png) and here.
    if route == '/img/map.png' then
        local data = atlasMapPng()
        if not data then return send(res, 404, 'html/img/map.png is missing', 'text/plain') end
        res.writeHead(200, { ['Content-Type'] = 'image/png', ['Cache-Control'] = 'max-age=3600',
                             ['X-Content-Type-Options'] = 'nosniff' })
        return res.send(data)
    end

    -- Atlas: boot
    if route == '/api/boot' then
        return json_(res, 200, atlasBoot())
    end

    -- Atlas: the six ops
    local op = route:match('^/api/(%a+)$')
    if op and ATLAS_OPS[op] ~= nil then
        return atlasApi(req, res, op)
    end

    -- The image
    if route == '/map' then
        local data, mime = mapImage()
        if not data then return send(res, 404, 'no map image', 'text/plain') end
        res.writeHead(200, { ['Content-Type'] = mime, ['Cache-Control'] = 'max-age=86400' })
        return res.send(data)
    end

    -- The node map
    -- Shares the resource, key, map image and calibration with the sector page, so nothing is duplicated. When the sector system is removed this page is what is left.
    if route == '/api/nodes' then
        return json_(res, 410, { ok = false,
            error = 'retired: the herd simulation was replaced. The atlas now uses /api/snapshot (see sv_http.lua WEB ATLAS).' })
    end

    -- State
    if route == '/api/state' then
        local z = zombies()
        if not z then return json_(res, 503, { ok = false, error = 'bs_zombies is not running' }) end

        return json_(res, 200, {
            ok = true,
            grid = z:SectorGrid(),
            sectors = z:SectorSnapshot(),
            hasMap = mapImage() ~= nil,
            calib = calibration(),
        })
    end

    -- Edit
    if route == '/api/set' then
        if req.method ~= 'POST' then
            return json_(res, 405, { ok = false, error = 'POST only' })
        end

        -- setDataHandler is the only way to read a body and it is a callback, so everything after must happen inside it or the request hangs.
        req.setDataHandler(function(body)
            local ok, data = pcall(json.decode, body or '')
            if not ok or type(data) ~= 'table' then
                return json_(res, 400, { ok = false, error = 'bad body' })
            end

            local z = zombies()
            if not z then return json_(res, 503, { ok = false, error = 'bs_zombies is not running' }) end

            if data.action == 'clearDebt' then
                local cleared = z:SectorClearDebt(data.key)
                return json_(res, 200, { ok = true, cleared = cleared, sectors = z:SectorSnapshot() })
            end

            -- Whitelisted server-side by ZSectors.Set; nothing arriving here is trusted to name a field.
            local applied = z:SectorSet(data.key, data.field, data.value)
            if not applied then
                return json_(res, 400, { ok = false, error = 'that field cannot be set' })
            end

            print(('^5[BeyondSurvival]^7 (sectormap) %s %s = %s')
                :format(tostring(data.key), tostring(data.field), tostring(data.value)))

            return json_(res, 200, { ok = true, sectors = z:SectorSnapshot() })
        end)
        return
    end

    -- Ground truth: where players actually are
    -- Calibration uses a coordinate the server is certain of (a player's position): click where that player is on the image. Two such points solve the mapping exactly.
    if route == '/api/players' then
        local out = {}
        for _, sid in ipairs(GetPlayers()) do
            local src = tonumber(sid)
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 then
                local at = GetEntityCoords(ped)
                out[#out + 1] = {
                    id = src,
                    name = GetPlayerName(src) or ('player ' .. src),
                    x = math.floor(at.x * 10) / 10,
                    y = math.floor(at.y * 10) / 10,
                }
            end
        end
        return json_(res, 200, { ok = true, players = out })
    end

    -- Upload a map image
    if route == '/api/map' then
        if req.method ~= 'POST' then
            return json_(res, 405, { ok = false, error = 'POST only' })
        end

        req.setDataHandler(function(body)
            local ok, data = pcall(json.decode, body or '')
            if not ok or type(data) ~= 'table' or type(data.data) ~= 'string' then
                return json_(res, 400, { ok = false, error = 'no image in that' })
            end

            local bytes = b64decode(data.data)
            if #bytes < 1024 then
                return json_(res, 400, { ok = false, error = 'that file is empty or not an image' })
            end
            if #bytes > MAX_MAP then
                return json_(res, 413, { ok = false,
                    error = ('too big - %dMB, limit is %dMB'):format(
                        math.floor(#bytes / 1048576), math.floor(MAX_MAP / 1048576)) })
            end

            -- Trust the bytes, not the browser's claimed type. A file whose magic number is not one of these will not render.
            local mime
            if bytes:sub(1, 8) == '\137PNG\r\n\26\n' then mime = 'image/png'
            elseif bytes:sub(1, 3) == '\255\216\255' then mime = 'image/jpeg'
            elseif bytes:sub(1, 4) == 'RIFF' and bytes:sub(9, 12) == 'WEBP' then mime = 'image/webp'
            else
                return json_(res, 415, { ok = false, error = 'not a PNG, JPEG or WebP' })
            end

            SaveResourceFile(RES, MAP_FILE, bytes, #bytes)
            SaveResourceFile(RES, MIME_FILE, mime, -1)

            mapCache, mapMime, mapChecked = bytes, mime, true

            print(('^2[BeyondSurvival]^7 (sectormap) new map image uploaded (%s, %dKB)')
                :format(mime, math.floor(#bytes / 1024)))

            return json_(res, 200, { ok = true, bytes = #bytes })
        end)
        return
    end

    -- Line it up
    if route == '/api/calibration' then
        if req.method ~= 'POST' then
            return json_(res, 405, { ok = false, error = 'POST only' })
        end

        req.setDataHandler(function(body)
            local ok, data = pcall(json.decode, body or '')
            if not ok or type(data) ~= 'table' then
                return json_(res, 400, { ok = false, error = 'bad body' })
            end

            local c = {}
            for _, f in ipairs({ 'minX', 'maxX', 'minY', 'maxY' }) do
                local v = tonumber(data[f])
                if not v then return json_(res, 400, { ok = false, error = 'bad ' .. f }) end
                -- Generous, but a box outside this is a typo, not a crop.
                c[f] = math.max(-20000, math.min(20000, v))
            end

            if c.maxX <= c.minX or c.maxY <= c.minY then
                return json_(res, 400, { ok = false, error = 'that box is inside out' })
            end

            SaveResourceFile(RES, CALIB_FILE, json.encode(c), -1)
            return json_(res, 200, { ok = true, calib = c })
        end)
        return
    end

    send(res, 404, 'Not found.\n', 'text/plain; charset=utf-8')
end)

-- Say where it is at boot
-- The URL contains a 32-character key, so it is printed in full, framed, once. Copy it from the console and bookmark it.

local function panelUrl()
    local port = GetConvar('netPort', '30120')
    return ('http://YOUR-SERVER-IP:%s/%s/?key=%s'):format(port, RES, token())
end

-- The node-simulation panel, same host and key. See the /nodes route.
local function nodeUrl()
    local port = GetConvar('netPort', '30120')
    return ('http://YOUR-SERVER-IP:%s/%s?key=%s'):format(port, RES, token())
end

CreateThread(function()
    Wait(4000)

    print('^2' .. string.rep('=', 74) .. '^7')
    print('^2[BeyondSurvival]^7  SECTOR MAP PANEL')
    print('')
    print('   ^5' .. panelUrl() .. '^7')
    print('')
    print('   ^5' .. nodeUrl() .. '^7   <- the NODE ATLAS (admin only - this key IS the gate)')
    print('')
    print('   Replace YOUR-SERVER-IP with the address you use for txAdmin.')
    print('   Bookmark it. Drag a screenshot of the GTA V map onto the page to')
    print('   put the real map behind the grid - no restart needed.')
    print('^2' .. string.rep('=', 74) .. '^7')
end)

-- /sectormap - prints the same URL in chat for an admin in game.
RegisterCommand('sectormap', function(src)
    local line = panelUrl()

    if src == 0 then
        print('^5[BeyondSurvival]^7 ' .. line)
        return
    end

    -- Staff only, checked properly: this prints the panel key.
    local staff = false
    if GetResourceState('bs_admin') == 'started' then
        local ok, admin = pcall(function() return exports.bs_admin:IsAdmin(src) end)
        staff = ok and admin == true
    end
    if not staff then return end

    TriggerClientEvent('chat:addMessage', src, {
        args = { '[SECTOR MAP]', line },
        color = { 200, 118, 58 },
    })
end, false)

-- /nodemap - the live herd map for an admin in game. Same staff check as /sectormap since it prints the key. A separate command so it is one word.
RegisterCommand('nodemap', function(src)
    local line = nodeUrl()

    if src == 0 then
        print('^5[BeyondSurvival]^7 ' .. line)
        return
    end

    -- Always answers, so a refusal is not mistaken for the command not existing. Either authority is accepted: the bs.admin ace or bs_admin's IsAdmin, since they are configured separately.
    local staff = IsPlayerAceAllowed(src, 'bs.admin')
    if not staff and GetResourceState('bs_admin') == 'started' then
        local ok, admin = pcall(function() return exports.bs_admin:IsAdmin(src) end)
        staff = ok and admin == true
    end

    if not staff then
        TriggerClientEvent('chat:addMessage', src, {
            args = { '[NODE ATLAS]',
                     'refused - needs the `bs.admin` ace or staff in bs_admin. '
                     .. '(this reply means the command exists and bs_sectormap is running)' },
            color = { 200, 60, 40 },
        })
        return
    end

    TriggerClientEvent('chat:addMessage', src, {
        args = { '[NODE ATLAS]', line },
        color = { 200, 118, 58 },
    })
end, false)
