-- bs_atlas - hands the map calibration (nodes/calibration.json) to the in-game atlas

local NODES_RES  = 'nodes'
local CALIB_FILE = 'calibration.json'
local IMAGE_URL  = 'nui://nodes/html/img/map.png'

-- Fallback box used when the file is missing; keep in step with DEFAULT_CALIB in nodes/server/sv_http.lua
local DEFAULT_CALIB = { minX = -4000, maxX = 5000, minY = -4000, maxY = 8000 }

--- Same staff gate as sv_sim_atlas.lua: console yes, bs_admin missing = no.
local function isStaff(src)
    if src == 0 then return true end
    if GetResourceState('bs_admin') ~= 'started' then return false end
    local ok, admin = pcall(function() return exports.bs_admin:IsAdmin(src) end)
    return ok and admin == true
end

local function validCalib(t)
    if type(t) ~= 'table' then return nil end
    local c = {}
    for _, k in ipairs({ 'minX', 'maxX', 'minY', 'maxY' }) do
        local v = tonumber(t[k])
        if not v or v ~= v then return nil end
        c[k] = v
    end
    if c.maxX <= c.minX or c.maxY <= c.minY then return nil end
    return c
end

BSB.RegisterCallback('bs_atlas:mapinfo', function(src)
    if not isStaff(src) then return { ok = false, error = Lp(src, 'atlas.sv.notstaff') } end

    local raw = LoadResourceFile(NODES_RES, CALIB_FILE)
    if not raw or raw == '' then
        return { ok = true, url = IMAGE_URL, calib = DEFAULT_CALIB,
                 note = Lp(src, 'atlas.sv.nocalibfile') }
    end

    local okJson, data = pcall(json.decode, raw)
    local c = okJson and validCalib(data) or nil
    if not c then
        -- A broken file is not replaced by the default: the page gets no box and says so.
        return { ok = false, error = Lp(src, 'atlas.sv.nocalib') }
    end

    return { ok = true, url = IMAGE_URL, calib = c }
end)

-- World cars from the bs_vehicles spawn system. Staff only, read only.
BSB.RegisterCallback('bs_atlas:cars', function(src)
    if not isStaff(src) then return { ok = false, error = Lp(src, 'atlas.sv.notstaff') } end
    if GetResourceState('bs_vehicles') ~= 'started' then
        return { ok = false, error = Lp(src, 'atlas.sv.novehicles') }
    end
    local ok, list = pcall(function() return exports.bs_vehicles:GetWorldCars() end)
    if not ok then return { ok = false, error = Lp(src, 'atlas.sv.novehicles') } end
    return { ok = true, cars = list or {} }
end)

-- Teleport from the map: staff only, logged to bs_guard_log (kind admin) like other admin actions
BSB.RegisterCallback('bs_atlas:teleport', function(src, args)
    if src == 0 or not isStaff(src) then return { ok = false, error = Lp(src, 'atlas.sv.notstaff') } end
    local x, y = tonumber(type(args) == 'table' and args.x), tonumber(type(args) == 'table' and args.y)
    if not x or not y or x ~= x or y ~= y or math.abs(x) > 12000 or math.abs(y) > 12000 then
        return { ok = false, error = Lp(src, 'atlas.sv.badpos') }
    end

    local ped = GetPlayerPed(src)
    local c = (ped and ped ~= 0) and GetEntityCoords(ped) or vector3(0.0, 0.0, 0.0)
    local player = exports.bs_core:GetPlayer(src)
    exports.oxmysql:insert(
        'INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,?,?,?,?,?)',
        { src, GetPlayerIdentifierByType(src, 'license'), player and player.charId or nil,
          (GetPlayerName(src) or '?'):sub(1, 64), 'admin', 0,
          ('atlas teleport to %.0f, %.0f'):format(x, y), c.x, c.y, c.z })
    return { ok = true, x = x, y = y }
end)
