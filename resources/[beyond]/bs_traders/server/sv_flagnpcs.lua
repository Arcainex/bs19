-- Player faction safezone flags work like a small town: copies of the town trader and mission giver stand
-- by the flag. Only that faction gets them in its spawn list and only they can use them, so the base stays hidden.

local Flag = {}  -- [npcId] = { factionId, x, y, z, h, template }
local PREFIX = 'flagnpc_'

local function rebuild(flags)
    local new = {}
    if Traders.Settings.factionSafezoneNpcs then
        for _, f in ipairs(flags or {}) do
            if f.kind == 'safezone' and f.status ~= 'removed' and f.x then
                for i, t in ipairs(Traders.Settings.factionSafezoneTemplates or {}) do
                    local o = t.offset or vector3(0.0, 0.0, 0.0)
                    new[('%s%d_%d'):format(PREFIX, tonumber(f.id) or 0, i)] = {
                        factionId = f.factionId, template = t.id, h = t.heading or 0.0,
                        x = f.x + o.x, y = f.y + o.y, z = f.z + o.z,
                    }
                end
            end
        end
    end
    local changed = json.encode(new) ~= json.encode(Flag)
    Flag = new
    if changed then TriggerClientEvent('bs:traders:reload', -1) end
end

local baseNpc, baseIds = Registry.EffectiveNpc, Registry.AllNpcIds
function Registry.EffectiveNpc(id)
    local f = Flag[id]
    if not f then return baseNpc(id) end
    local t = baseNpc(f.template)
    if not t then return nil end
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    c.id, c.coords, c.heading, c.hasConfig, c.factionId = id, vector3(f.x, f.y, f.z), f.h, false, f.factionId
    return c
end
function Registry.AllNpcIds()
    local out = baseIds()
    for id in pairs(Flag) do out[#out + 1] = id end
    return out
end

-- Town NPCs are for everyone, flag NPCs only for their faction.
function FlagNpcAllowed(src, id)
    local f = Flag[id]
    if not f then return true end
    local ok, s = pcall(function() return exports.bs_factions:GetFactionSummary(tonumber(src)) end)
    return ok and s and s.factionId == f.factionId or false
end

AddEventHandler('bs:factionBases:changed', function(flags) rebuild(flags) end)
CreateThread(function()
    while true do
        if GetResourceState('bs_faction_bases') == 'started' then
            local ok, flags = pcall(function() return exports.bs_faction_bases:ListFlags() end)
            if ok then rebuild(flags) end
        end
        Wait(60000) -- also picks up the F1 switch
    end
end)
