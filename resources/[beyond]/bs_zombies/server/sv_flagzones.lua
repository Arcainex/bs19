-- bs_zombies - keeps faction safezone flags in Zones.Safe on the server
local function refresh(flags)
    if type(flags) == 'table' then Zones.SetFlagZones(flags) end
end

-- bs_faction_bases fires this on every flag change.
AddEventHandler('bs:factionBases:changed', function(flags) refresh(flags) end)

CreateThread(function()
    while true do
        if GetResourceState('bs_faction_bases') == 'started' then
            local ok, flags = pcall(function() return exports.bs_faction_bases:ListFlags() end)
            if ok then refresh(flags) end
        end
        Wait(15000)
    end
end)

local function posOf(record)
    if record.ent and DoesEntityExist(record.ent) then
        local c = GetEntityCoords(record.ent)
        return c.x, c.y
    end
    return record.x, record.y
end

-- Despawn sweep, flag zones only (town safezones keep their own rules).
CreateThread(function()
    while true do
        Wait(5000)
        local zones = {}
        for _, z in ipairs(Zones.Safe or {}) do if z.flag then zones[#zones + 1] = z end end
        if #zones > 0 and Registry and Registry.zombies and Registry.Remove then
            local kill = {}
            for id, record in pairs(Registry.zombies) do
                local x, y = posOf(record)
                if x and y then
                    for _, z in ipairs(zones) do
                        local dx, dy = x - z.coords.x, y - z.coords.y
                        if dx * dx + dy * dy <= z.radius * z.radius then kill[#kill + 1] = id break end
                    end
                end
            end
            for _, id in ipairs(kill) do pcall(Registry.Remove, id, 'flagzone') end
        end
    end
end)
