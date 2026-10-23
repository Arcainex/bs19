-- bs_zombies - adapter that keeps the old ZNodes names

ZNodes = ZNodes or {}

-- Compat surface. ready gates every caller and stays false until the grid has finished building.
ZNodes.ready = false

-- Diagnostics only (/zstream, boot banner)
ZNodes.nodes = {}

-- sv_streaming decrements totalPopulation on every spawn
ZNodes.campaign = { totalPopulation = 0, simTimeMs = 0 }

-- Helpers

-- One individual dressed as a node. radius is 6 m
local function view(a)
    if not a then return nil end
    return {
        id = a.id,
        x = a.x, y = a.y, z = a.z or 0.0,
        radius = 6.0,
        population = a.pedId and 0 or 1,
        intent = a.state or 'wander',
        -- The planner refuses alerted nodes near a live POI
        alert = (a.state == 'drawn' or a.state == 'hunt'),
    }
end

-- THE EIGHT NAMES

-- Not called anymore now that the simulation boots itself; kept as a no-op so old callers do not hit a nil index
function ZNodes.Bind(record)
    local a = ZSim and ZSim.agents[record.nodeId]
    if not a or a.pedId then return false end
    a.pedId = record.id
    a.x, a.y, a.z = record.x, record.y, record.z
    local target=a.target
    if target and target.until_ and target.until_ > GetGameTimer() then
        record.poiX,record.poiY,record.poiZ=target.x,target.y,record.z
        record.poiUntil=os.time()+math.ceil((target.until_-GetGameTimer())/1000)
    end
    return true
end

function ZNodes.Release(record)
    local a = ZSim and ZSim.agents[record.nodeId]
    if a and a.pedId == record.id then
        a.x, a.y, a.z = record.x, record.y, record.z
        a.pedId = nil
    end
end

function ZNodes.Init() return ZSim and ZSim.ready or false end

-- Planner candidates: nearest first, individuals only, never one that already has a ped
function ZNodes.Nearby(coords, radius)
    if not ZSim or not ZSim.ready then return {} end
    local x = coords.x or coords[1]
    local y = coords.y or coords[2]
    if not x or not y then return {} end

    local list = ZSim.AgentsNear(x, y, radius or 300.0)
    local out, n = {}, 0
    for i = 1, #list do
        local a = list[i]
        if not a.pedId then
            n = n + 1
            out[n] = view(a)
        end
    end
    return out
end

function ZNodes.Get(id)
    local a = ZSim and ZSim.agents and ZSim.agents[tonumber(id) or -1]
    return view(a)
end

-- A walker died
function ZNodes.RecordDeath(nodeId, coords)
    if not ZSim or not ZSim.ready then return false end
    return ZSim.RecordDeath(tonumber(nodeId), coords and coords.x, coords and coords.y)
end

-- Deliberate no-op. Noise used to relocate whole herds onto the noise point.
local warnedApplyNoise = false
function ZNodes.ApplyNoise()
    if not warnedApplyNoise then
        warnedApplyNoise = true
        print('^3[BS SIM]^7 ZNodes.ApplyNoise was called. It is a no-op by design - '
            .. 'see the comment in sv_sim_compat.lua. Noise now moves individuals, not populations.')
    end
    return 0
end

-- Diagnostics surface, answered from the simulation so /zstream's boot banner does not print zeros
function ZNodes.PendingNodeCount() return 0 end
function ZNodes.Snapshot()
    return { nodes = ZNodes.nodes, total = (ZSim and ZSim.stats.total) or 0 }
end

-- RECONCILIATION + THE SLOW DIAGNOSTIC REBUILD
-- One thread, 1 Hz, two bounded passes. See the header for why this is a poll.

CreateThread(function()
    while true do
        Wait(1000)

        if Sim and Sim.enabled and ZSim and ZSim.ready then
            ZNodes.ready = true

            -- PASS 1: which individuals currently own a ped?
            local live = {}
            local zombies = (Registry and Registry.zombies) or {}
            for _, record in pairs(zombies) do
                local nid = record.nodeId
                if nid and nid > 0 then
                    local a = ZSim.agents[nid]
                    if a and a.pedId == record.id then
                        -- The ped is the authority while it exists
                        if record.x and record.y then
                            a.x, a.y, a.z = record.x, record.y, record.z or 0.0
                        end
                        live[nid] = true
                    end
                end
            end

            -- PASS 2: clear the mark on anything whose ped has gone.
            for _, a in pairs(ZSim.agents) do
                if a.pedId and not live[a.id] then a.pedId = nil end
            end

            ZNodes.campaign.totalPopulation = ZSim.stats.total
            ZNodes.campaign.simTimeMs = GetGameTimer()
        end
    end
end)

-- The diagnostics table. Slow: nothing hot reads it.
CreateThread(function()
    while true do
        Wait(5000)
        if ZSim and ZSim.ready then
            local out = {}
            for id, a in pairs(ZSim.agents) do out[id] = view(a) end
            ZNodes.nodes = out
        end
    end
end)
