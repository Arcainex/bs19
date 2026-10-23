-- bs_zombies - staff zombie debug overlay (hold Left Alt)

local cfg = (Zombies.Settings and Zombies.Settings.debugOverlay) or {}
local KEY = cfg.control or 19
local visibleDistance = cfg.visibleDistance or 160.0
local simulatedRadius = cfg.simulatedRadius or 260.0
local simulatedLimit = cfg.simulatedLimit or 40
local refreshMs = cfg.refreshMs or 500
local simulated, lastRequest, requestPending = {}, 0, false

local function drawWorldText(x, y, z, text, r, g, b)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)
    if not onScreen then return end
    SetTextScale(0.28, 0.28)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(r, g, b, 220)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(sx, sy)
end

local function refreshSimulated()
    if requestPending then return end
    requestPending = true
    CreateThread(function()
        local reply = BSB.Await('zombies:debug:nearby', 1500, {
            radius = simulatedRadius,
            limit = simulatedLimit,
        })
        simulated = (reply and reply.ok and reply.agents) or {}
        requestPending = false
    end)
end

CreateThread(function()
    while true do
        if cfg.enabled ~= false and IsControlPressed(0, KEY) then
            local now = GetGameTimer()
            if now - lastRequest >= refreshMs then
                lastRequest = now
                refreshSimulated()
            end

            local me = GetEntityCoords(PlayerPedId())
            local max2 = visibleDistance * visibleDistance
            for _, entry in pairs(Zed.live or {}) do
                local ped = entry.ped
                if ped and DoesEntityExist(ped) and not IsEntityDead(ped) then
                    local p = GetEntityCoords(ped)
                    local dx, dy = p.x - me.x, p.y - me.y
                    if (dx * dx + dy * dy) <= max2 then
                        local rec = entry.rec or {}
                        local active = rec.d or entry.id
                        local sim = rec.nodeId or rec.n
                        local label = sim and ('A%d  D%s'):format(active, tostring(sim))
                                          or ('A%d'):format(active)
                        drawWorldText(p.x, p.y, p.z + 1.12, label, 255, 174, 74)
                    end
                end
            end

            for _, agent in ipairs(simulated) do
                if agent and agent.x and agent.y then
                    drawWorldText(agent.x, agent.y, (agent.z or me.z) + 1.05,
                        ('D%s'):format(tostring(agent.id)), 104, 194, 255)
                end
            end
            Wait(0)
        else
            Wait(120)
        end
    end
end)