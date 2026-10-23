-- Mission Log tab. Any resource can list missions here: call exports.bs_inventory:RegisterMissionSource(GetCurrentResourceName())
-- and export MissionLogList(src) -> { { id, title, steps = { { label, done } }, complete, claimed } } and
-- MissionLogClaim(src, id) -> { ok, error }. The provider validates and pays the reward; this file only routes.
-- Optional entry fields: group (header text), hint (note under the steps), noClaim (progress only, no button).

local Sources = {}   -- [resourceName] = true

exports('RegisterMissionSource', function(res)
    if type(res) == 'string' and res ~= '' then Sources[res] = true end
    return true
end)

AddEventHandler('onResourceStop', function(res) Sources[res] = nil end)

BSB.RegisterCallback('inventory:missions', function(src)
    local out = {}
    for res in pairs(Sources) do
        if GetResourceState(res) == 'started' then
            local ok, list = pcall(function() return exports[res]:MissionLogList(src) end)
            if ok and type(list) == 'table' then
                for _, m in ipairs(list) do
                    if type(m) == 'table' and m.id then
                        m.source = res
                        if type(m.group) ~= 'string' or m.group == '' then
                            local key = 'mlog.src.' .. res
                            local txt = Lp(src, key)
                            m.group = (txt ~= key) and txt or Lp(src, 'mlog.src.other')
                        end
                        out[#out + 1] = m
                    end
                end
            end
        end
    end
    -- Grouped by header, then unclaimed first, then by title.
    table.sort(out, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        if (a.claimed == true) ~= (b.claimed == true) then return not a.claimed end
        return tostring(a.title) < tostring(b.title)
    end)
    return out
end)

BSB.RegisterCallback('inventory:missionClaim', function(src, res, id)
    if type(res) ~= 'string' or not Sources[res] or GetResourceState(res) ~= 'started' then return { ok = false } end
    local ok, r = pcall(function() return exports[res]:MissionLogClaim(src, tostring(id or '')) end)
    return (ok and type(r) == 'table') and r or { ok = false }
end)
