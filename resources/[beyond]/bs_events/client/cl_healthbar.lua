-- bs_events - health bars over convoy escorts (state bag bsConvoy), same look as the zombie health bar
local RANGE, LINGER = 60.0, 5000
local seen = {}   -- [ped] = last aimed ms

-- Export result cached for 500 ms (the loop below runs every frame).
local enCache, enAt = false, -1000
local function enabled()
    local now = GetGameTimer()
    if now - enAt >= 500 then
        enAt = now
        local ok, on = pcall(function() return exports.bs_zombies:HealthBarsVisible() end)
        enCache = ok and on == true
    end
    return enCache
end

local function drawBar(x, y, w, h, frac, a)
    frac = math.max(0.0, math.min(1.0, frac))
    DrawRect(x, y, w + 0.002, h + 0.0022, 10, 10, 9, math.floor(170 * a))
    local fw = w * frac
    if fw > 0.0 then DrawRect(x - (w - fw) / 2.0, y, fw, h, 90, 140, 90, math.floor(235 * a)) end
end

CreateThread(function()
    while true do
        if not enabled() then
            if next(seen) then seen = {} end
            Wait(500)
        else
            Wait(0)
            local me, now = PlayerPedId(), GetGameTimer()
            local ok, ent = GetEntityPlayerIsFreeAimingAt(PlayerId())
            if ok and ent and ent ~= 0 and DoesEntityExist(ent) and IsEntityAPed(ent)
               and NetworkGetEntityIsNetworked(ent) and Entity(ent).state.bsConvoy then
                seen[ent] = now
            end
            local mc = GetEntityCoords(me)
            for ped, at in pairs(seen) do
                if now - at > LINGER or not DoesEntityExist(ped) or IsEntityDead(ped) then
                    seen[ped] = nil
                else
                    local pc = GetEntityCoords(ped)
                    if #(mc - pc) < RANGE and HasEntityClearLosToEntity(me, ped, 17) then
                        local on, sx, sy = GetScreenCoordFromWorldCoord(pc.x, pc.y, pc.z + 1.05)
                        if on then
                            local max = math.max(1, GetEntityMaxHealth(ped) - 100)
                            local frac = (GetEntityHealth(ped) - 100) / max
                            local a = math.min(1.0, (LINGER - (now - at)) / 1000.0)
                            drawBar(sx, sy, 0.055, 0.0075, frac, a)
                        end
                    end
                end
            end
        end
    end
end)
