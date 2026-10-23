-- bs_guard - teleport / speed / super jump / noclip heuristics from server-side position samples (OneSync)

local G = GuardCore
local M = Guard.Movement
local state = {}   -- [src] = { pos, at, speedStrikes, riseStrikes, veh }

G.onAllow = function(src) state[src] = nil end   -- re-baseline after any legit move
G.onDrop[#G.onDrop + 1] = function(src) state[src] = nil end

local AIR = { heli = true, plane = true, blimp = true }

local function vehKind(veh)
    if not veh or veh == 0 then return nil end
    local ok, t = pcall(GetVehicleType, veh)
    return ok and t or 'automobile'
end

local function flat(a, b) local dx, dy = a.x - b.x, a.y - b.y; return math.sqrt(dx * dx + dy * dy) end

local function sample(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then state[src] = nil return end
    if GetEntityHealth(ped) <= 0 then state[src] = nil return end
    local pos = GetEntityCoords(ped)
    local t = GetGameTimer()
    local veh = GetVehiclePedIsIn(ped, false)
    local s = state[src]
    if not s or G.inGrace(src) or G.IsAllowed(src, 'teleport') or (s.veh ~= veh) then
        state[src] = { pos = pos, at = t, speedStrikes = 0, riseStrikes = 0, veh = veh }
        return
    end
    local dt = (t - s.at) / 1000.0
    if dt < 0.25 then return end
    local d3 = #(pos - s.pos)
    local dh = flat(pos, s.pos)
    local dz = pos.z - s.pos.z
    s.pos, s.at = pos, t

    -- attached to something (towed, carried, in a trunk) moves with the parent
    if IsEntityAttached and IsEntityAttached(ped) then s.speedStrikes, s.riseStrikes = 0, 0 return end

    -- 1) teleport: a jump no vehicle could make in one sample
    if d3 > (M.teleportDist or 150.0) * math.max(1.0, dt) then
        G.Flag(src, 'teleport', ('moved %.0fm in %.1fs%s'):format(d3, dt, veh ~= 0 and ' (in vehicle)' or ''),
            d3 > 600 and 90 or 70)
        s.speedStrikes = 0
        return
    end

    -- 2) speed
    local kind = vehKind(veh)
    local limit, speed
    if not kind then limit, speed = M.onFootMax or 13.0, dh / dt
    elseif AIR[kind] then limit, speed = M.airMax or 150.0, d3 / dt
    else limit, speed = M.vehicleMax or 85.0, dh / dt end
    if speed > limit then
        s.speedStrikes = s.speedStrikes + 1
        if s.speedStrikes >= (M.speedStrikes or 3) then
            G.Flag(src, 'speed', ('%.1f m/s (limit %.0f, %s) for %d ticks'):format(speed, limit, kind or 'on foot', s.speedStrikes),
                speed > limit * 2 and 85 or 60)
            s.speedStrikes = 0
        end
    else
        s.speedStrikes = 0
    end

    -- 3) on foot vertical: super jump / noclip
    if not kind then
        local rise = dz / dt
        if rise > (M.jumpRise or 5.0) then
            G.Flag(src, 'superjump', ('rose %.1fm in %.1fs on foot'):format(dz, dt), rise > (M.jumpRise or 5.0) * 2 and 80 or 55)
        end
        if rise > (M.noclipRise or 1.6) then
            s.riseStrikes = s.riseStrikes + 1
            if s.riseStrikes >= (M.noclipStrikes or 4) then
                local extra = ''
                local okC, noCol = pcall(function() return GetEntityCollisionDisabled(ped) end)
                if okC and noCol then extra = ', collision off' end
                local okV, vis = pcall(IsEntityVisible, ped)
                if okV and vis == false then extra = extra .. ', invisible' end
                G.Flag(src, 'noclip', ('rising on foot %d ticks (last %.1f m/s)%s'):format(s.riseStrikes, rise, extra),
                    extra ~= '' and 85 or 60)
                s.riseStrikes = 0
            end
        else
            s.riseStrikes = 0
        end
        -- invisible + no collision on foot with movement = noclip-style menu
        if dh / dt > 3.0 then
            local okC, noCol = pcall(function() return GetEntityCollisionDisabled(ped) end)
            local okV, vis = pcall(IsEntityVisible, ped)
            if okC and noCol and okV and vis == false then
                G.Flag(src, 'noclip', ('moving %.1f m/s invisible with collision off'):format(dh / dt), 80)
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(M.tickMs or 1000)
        if Guard.Settings.enabled and M.enabled then
            for _, id in ipairs(GetPlayers()) do
                local src = tonumber(id)
                if src and not G.isExempt(src) then
                    local ok, err = pcall(sample, src)
                    if not ok then G.dbg('movement sample failed: %s', tostring(err)) end
                end
            end
        end
    end
end)
